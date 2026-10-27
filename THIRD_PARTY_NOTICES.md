# Third-party notices

VenusBar includes adapted SwiftfulUI primitives for pressed button feedback and card backgrounds. The original components are `ButtonStyleViewModifier.swift` and `BackgroundBorderAndFillViewModifier.swift` from [SwiftfulUI](https://github.com/SwiftfulThinking/SwiftfulUI). Their scale/opacity/brightness and border/fill geometry are used in `Sources/VenusBar/SwiftfulUIPrimitives.swift`.

The adaptations preserve native SwiftUI Button semantics, support Reduce Motion, and use animations available on macOS 13. No complete SwiftfulUI package or its transitive dependencies are included.

Original sources:

- https://github.com/SwiftfulThinking/SwiftfulUI/blob/main/Sources/SwiftfulUI/Buttons/ButtonStyleViewModifier.swift
- https://github.com/SwiftfulThinking/SwiftfulUI/blob/main/Sources/SwiftfulUI/Backgrounds/BackgroundBorderAndFillViewModifier.swift

## SwiftfulUI — MIT License

Copyright (c) 2022 Swiftful Thinking, LLC

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
