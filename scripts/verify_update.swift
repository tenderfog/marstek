import Foundation
import CryptoKit

struct UpdateManifest: Decodable {
    let version: String
    let build: Int
    let sourceCommit: String
    let runID: Int
    let artifactName: String
    let zipSHA256: String
}

func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw NSError(domain: "VenusBar.UpdateVerification", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

do {
    let arguments = CommandLine.arguments
    try require(arguments.count == 5, "Usage: verify_update PUBLIC_KEY ZIP APPCAST MANIFEST")
    let publicKeyText = try String(contentsOfFile: arguments[1], encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let publicKeyData = Data(base64Encoded: publicKeyText), publicKeyData.count == 32 else {
        throw NSError(domain: "VenusBar.UpdateVerification", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid Ed25519 public key"])
    }
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
    let manifest = try JSONDecoder().decode(UpdateManifest.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[4])))
    try require(manifest.version.range(of: #"^[0-9]+(?:\.[0-9]+){1,2}$"#, options: .regularExpression) != nil && manifest.build > 0, "Invalid release version or build")
    try require(manifest.sourceCommit.range(of: #"^[a-f0-9]{40}$"#, options: .regularExpression) != nil && manifest.runID > 0 && manifest.artifactName == "VenusBar-universal", "Invalid build provenance")
    try require(manifest.zipSHA256.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil, "Invalid archive checksum")
    let archive = try Data(contentsOf: URL(fileURLWithPath: arguments[2]), options: .mappedIfSafe)
    let digest = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
    try require(digest == manifest.zipSHA256, "Archive SHA-256 does not match the reviewed manifest")

    let feed = try Data(contentsOf: URL(fileURLWithPath: arguments[3]))
    try require(feed.count <= 1_048_576, "Appcast is too large")
    let marker = Data("<!-- sparkle-signatures:\n".utf8)
    guard let markerRange = feed.range(of: marker, options: .backwards) else {
        throw NSError(domain: "VenusBar.UpdateVerification", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing Sparkle feed signature"])
    }
    let signedContent = feed.prefix(markerRange.lowerBound)
    let suffix = String(decoding: feed[markerRange.lowerBound...], as: UTF8.self)
    let pattern = #"\A<!-- sparkle-signatures:\nedSignature: ([A-Za-z0-9+/]+={0,2})\nlength: ([0-9]+)\n-->\n?\z"#
    let regex = try NSRegularExpression(pattern: pattern)
    guard suffix.utf8.count < 512,
          let match = regex.firstMatch(in: suffix, range: NSRange(suffix.startIndex..., in: suffix)),
          let signatureRange = Range(match.range(at: 1), in: suffix),
          let lengthRange = Range(match.range(at: 2), in: suffix),
          let feedSignature = Data(base64Encoded: String(suffix[signatureRange])), feedSignature.count == 64,
          let expectedLength = Int(suffix[lengthRange]), expectedLength == signedContent.count else {
        throw NSError(domain: "VenusBar.UpdateVerification", code: 4, userInfo: [NSLocalizedDescriptionKey: "Malformed Sparkle feed signature or length"])
    }
    try require(publicKey.isValidSignature(feedSignature, for: signedContent), "Appcast Ed25519 signature does not match the trusted public key")

    let document = try XMLDocument(data: Data(signedContent), options: [.nodeLoadExternalEntitiesNever])
    let items = try document.nodes(forXPath: "/rss/channel/item")
    guard items.count == 1, let item = items.first as? XMLElement else {
        throw NSError(domain: "VenusBar.UpdateVerification", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected exactly one appcast item"])
    }
    let namespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"
    let versions = item.elements(forLocalName: "version", uri: namespace)
    let shortVersions = item.elements(forLocalName: "shortVersionString", uri: namespace)
    try require(versions.count == 1 && versions[0].stringValue == String(manifest.build), "Appcast build does not match the manifest")
    try require(shortVersions.count == 1 && shortVersions[0].stringValue == manifest.version, "Appcast version does not match the manifest")
    let enclosures = item.elements(forName: "enclosure")
    try require(enclosures.count == 1, "Expected exactly one update archive")
    let enclosure = enclosures[0]
    let expectedURL = "https://github.com/tenderfog/marstek/releases/download/v\(manifest.version)-build\(manifest.build)/VenusBar.zip"
    try require(enclosure.attribute(forName: "url")?.stringValue == expectedURL, "Appcast download URL is not the intended release asset")
    try require(enclosure.attribute(forName: "length")?.stringValue == String(archive.count), "Appcast archive length is incorrect")
    guard let signatureText = enclosure.attribute(forLocalName: "edSignature", uri: namespace)?.stringValue,
          let archiveSignature = Data(base64Encoded: signatureText), archiveSignature.count == 64 else {
        throw NSError(domain: "VenusBar.UpdateVerification", code: 6, userInfo: [NSLocalizedDescriptionKey: "Missing archive Ed25519 signature"])
    }
    try require(publicKey.isValidSignature(archiveSignature, for: archive), "Archive Ed25519 signature does not match the trusted public key")
    print("Verified signed feed, archive and release manifest for VenusBar \(manifest.version) build \(manifest.build).")
} catch {
    fputs("Update verification failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
