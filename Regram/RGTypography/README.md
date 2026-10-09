# Regram typography

Bundled unmodified OFL typefaces: JetBrains Mono 2.304, JetBrains Mono NL 2.304, Inter 4.1, Poppins, Lora, IBM Plex Sans/Serif/Mono/Sans SC, Source Sans 3 and Source Serif 4. The 11 bundled families include 82 faces. Plex Sans SC covers Chinese with upright Regular, Medium, SemiBold and Bold; its italic emphasis uses an oblique descriptor. Source Serif has no Medium face, so that weight uses its Regular face. Other bundled families include real Medium, Semibold and Bold with matching italics.

Upstream commits, unmodified download URLs, archive members and SHA-256 hashes are recorded in FONT-SOURCES.json. Original OFL 1.1 copyright and license notices are retained under Licenses/ and packaged with the app. Poppins and Lora are named in Anthropic's public brand-style example at https://github.com/anthropics/skills/blob/main/skills/brand-guidelines/SKILL.md. They are offered under their own names; no Anthropic Sans/Serif/Mono font files are bundled because no redistribution grant was identified.

Fonts are registered lazily per family and process. Their actual PostScript names are read from CoreText descriptors: font filenames do not reliably match those names (for example, Plex abbreviates some weights). Missing resources fall back to UIKit; missing glyphs use the text renderer's normal fallback cascade.

The default is the system font. Chat messages and the main interface can be enabled independently. Display's explicit monospace, serif, rounded and camera designs are preserved; large emoji remain system-rendered. Plain and rich message renderers carry the message role through formatting and nested blocks. Font cache keys include the selected family. Appearance changes refresh presentation data and per-chat/forced themes without changing their colors or wallpapers.

Tests: AppearancePolicyTests.swift is a standalone Foundation executable. `//Regram/RGTypography:TypographyTests` runs UIKit resource, scope, cache, notification, persistence and mixed-glyph rendering checks in an isolated test application, with no Telegram account or database.
