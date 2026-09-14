<div align="center">

# Mr. Blindbandit App

### Native iOS companion for the Mr. Blindbandit platform

**Accessible by design • Security-conscious • Creator-focused • Built with SwiftUI**

[![Website](https://img.shields.io/badge/Website-mrblindbandit.net-111111?style=for-the-badge&logo=googlechrome&logoColor=white)](https://mrblindbandit.net)
[![Platform](https://img.shields.io/badge/Platform-iOS_17%2B-000000?style=for-the-badge&logo=apple&logoColor=white)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-SwiftUI-F05138?style=for-the-badge&logo=swift&logoColor=white)](#technology-stack)
[![Accessibility](https://img.shields.io/badge/Accessibility-VoiceOver_First-111111?style=for-the-badge)](#accessibility)
[![Build](https://img.shields.io/github/actions/workflow/status/mrblindbandit/mr.-Blindbandit-app/ios.yml?style=for-the-badge&label=Unsigned%20IPA%20Build)](https://github.com/mrblindbandit/mr.-Blindbandit-app/actions/workflows/ios.yml)

**Repository:** `mrblindbandit/mr.-Blindbandit-app`

</div>

---

## Table of Contents

- [Overview](#overview)
- [Why This App Exists](#why-this-app-exists)
- [Project Status](#project-status)
- [Core Principles](#core-principles)
- [Current Features](#current-features)
- [Navigation](#navigation)
- [Security Model](#security-model)
- [Authentication and Session Behavior](#authentication-and-session-behavior)
- [Accessibility](#accessibility)
- [Web Integration](#web-integration)
- [Architecture](#architecture)
- [Technology Stack](#technology-stack)
- [Repository Structure](#repository-structure)
- [Requirements](#requirements)
- [Local Development](#local-development)
- [Building an Unsigned IPA](#building-an-unsigned-ipa)
- [GitHub Actions](#github-actions)
- [Installing an Unsigned Build](#installing-an-unsigned-build)
- [Configuration](#configuration)
- [Privacy](#privacy)
- [Security Boundaries](#security-boundaries)
- [Testing Strategy](#testing-strategy)
- [Accessibility Testing Checklist](#accessibility-testing-checklist)
- [Beta Testing](#beta-testing)
- [Bug Reports](#bug-reports)
- [Troubleshooting](#troubleshooting)
- [Roadmap](#roadmap)
- [Development Philosophy](#development-philosophy)
- [Responsible Security Reporting](#responsible-security-reporting)
- [About Mr. Blindbandit](#about-mr-blindbandit)

---

# Overview

The **Mr. Blindbandit App** is a native iOS companion for the broader **Mr. Blindbandit** platform and **Blindbandit Records** ecosystem.

It is designed to provide a focused, mobile-first entry point into the website, account area, media tools, community, and label portal while adding native iOS behavior around navigation, device authentication, privacy, and accessibility.

This project is intentionally not just a thin one-screen wrapper around a website.

The app combines:

- Native SwiftUI navigation
- Native iOS tabs
- Device-owner authentication
- Automatic app relocking
- Native settings and security controls
- WKWebView-based first-party website integration
- Website session persistence inside the app
- A deliberate separation between local device security and server-side account security
- VoiceOver-conscious controls and labels
- Controlled handling of first-party and external links
- A GitHub Actions pipeline that builds an unsigned IPA

The app is currently designed as a **private companion application** connected to `mrblindbandit.net`.

---

# Why This App Exists

Mr. Blindbandit is growing beyond a traditional artist website.

The platform includes music, creator tools, account features, media utilities, community functionality, and a private label portal. A native app provides a cleaner way to bring those systems together on iPhone without forcing every action through a generic browser tab.

The goals are straightforward:

1. **Make the Mr. Blindbandit platform faster to reach on mobile.**
2. **Provide native app navigation for the most important areas.**
3. **Add a device-level privacy gate before private content is shown.**
4. **Preserve the website's existing account and server authorization model.**
5. **Avoid bundling private backend secrets in the client.**
6. **Keep accessibility central to every native interaction.**
7. **Use the website as the source of truth for web content instead of duplicating the entire platform inside the app.**
8. **Keep the app architecture small enough to evolve quickly.**

The long-term direction is to create a native mobile layer around the wider Mr. Blindbandit ecosystem while keeping secure server-side behavior on the server.

---

# Project Status

> **Status: Active development / private companion build**

This repository represents an evolving iOS application rather than a finished App Store product.

Current characteristics:

- Native iOS application
- SwiftUI user interface
- iOS 17 minimum deployment target
- First-party website integration through WKWebView
- Device authentication gate
- Automated unsigned IPA generation
- No App Store signing configuration stored in the repository
- No production signing certificates stored in source control
- No private server secrets intended to be bundled with the application

The project may change significantly as native capabilities, platform APIs, account flows, media features, and distribution methods evolve.

---

# Core Principles

## 1. Accessibility first

The app is being designed by a blind creator who uses VoiceOver and assistive technology directly.

Accessibility is not treated as a final QA pass. It is part of the architecture, navigation, labeling, error handling, and interaction design from the beginning.

## 2. Server permissions remain server permissions

Unlocking the iOS application does **not** bypass website authentication or label-portal authorization.

The device lock protects access to the local app interface. The website and backend remain responsible for determining what an authenticated user may access.

## 3. No private backend secrets in the app

Client applications should be treated as inspectable.

The app therefore relies on existing website authentication and server-side authorization rather than embedding reusable private backend credentials in the application binary.

## 4. Native where native makes sense

The app uses native SwiftUI for the shell, navigation, device security, settings, and mobile behavior while allowing the website to remain the source of truth for connected web features.

## 5. Clear failure states

Users should not be left on a blank screen when something fails.

Loading, network failures, browser process failures, authentication failures, and session-clearing actions are surfaced with understandable UI wherever possible.

## 6. Practical over complicated

The project deliberately favors a small, understandable architecture over unnecessary abstraction.

The goal is to ship useful behavior, test it, improve it, and expand carefully.

---

# Current Features

## Native device lock

The app uses `LocalAuthentication` and the device-owner authentication policy.

Depending on the iPhone and device configuration, this can use:

- Face ID
- Touch ID
- Device passcode

The first time the user opens the protected experience, the app asks them to configure secure unlock.

If device-owner authentication is unavailable, the app explains that Face ID, Touch ID, or a device passcode must be configured in iPhone Settings.

## Automatic background locking

When the application enters the background, it relocks.

This helps prevent private content from remaining immediately visible if the device changes hands after the app has been opened.

## Background privacy cover

When the app is not active, the interface is covered with a private screen rather than leaving the active app content exposed.

This is intended to reduce accidental disclosure in app switching and background states.

## Native tab navigation

The current app shell provides four primary tabs:

- **Home**
- **Profile**
- **Label**
- **Settings**

Each is represented with a native SwiftUI tab item and system icon.

## Home shortcuts

The native Home screen currently provides direct navigation to:

- Public home
- Media tools
- Community
- Sign in
- Label dashboard
- Payment overview

It also includes a native Share action for the public website.

## Connected profile screen

The Profile tab opens the website account area within the app's controlled web surface.

## Connected label dashboard

The Label tab provides direct access to the label portal while still relying on server-side permissions.

## Native app settings

The Settings area contains controls and information for:

- Device lock status
- Manual app locking
- Clearing website sessions stored by the app
- Accessibility information
- Opening iOS app settings
- Account and security navigation
- Application version information

## Session clearing

Users can clear website cookies and stored website data associated with the app's WKWebView session.

The app presents a destructive confirmation dialog before clearing those sessions.

After clearing the web data, the app relocks.

## Browser loading state

When a page is loading, the app exposes a visible and accessible loading indicator.

## Browser error recovery

If a page fails to load, the user receives a readable error message and a **Retry loading** button instead of a blank web view.

If the WebKit content process stops responding, the user receives a specific message and can reload.

## Native browser toolbar

Website screens include native controls for:

- Back
- Forward
- Reload
- Open in Safari

## First-party link handling

The embedded browser is intentionally selective about which domains remain inside the app.

Current first-party host handling includes:

- `mrblindbandit.net`
- `www.mrblindbandit.net`
- `portal.mrblindbandit.net`
- `clerk.mrblindbandit.net`
- `accounts.mrblindbandit.net`

External HTTPS links are opened through the system instead of silently being treated as trusted internal navigation.

## JavaScript dialog support

Website-driven JavaScript dialogs are mapped into native iOS alerts for:

- Alert messages
- Confirmation prompts
- Text input prompts

Text input receives an accessibility label based on the website prompt.

---

# Navigation

The app currently uses a four-tab structure.

## Home

The Home tab acts as the native dashboard and entry point.

It contains:

- Mr. Blindbandit identity and branding
- Website shortcuts
- Label shortcuts
- Sharing functionality

## Profile

The Profile tab routes to the connected account area.

This is intended to centralize personal account and security-related web functionality while retaining the app's native shell.

## Label

The Label tab routes to the private label portal.

Visibility inside the portal still depends on website authentication and backend permissions.

## Settings

The Settings tab contains device-security, session, accessibility, account, and app-information controls.

---

# Security Model

Security in this project is intentionally layered.

The app does **not** treat one successful Face ID or passcode check as proof that the user should automatically gain backend access.

Instead, security is separated into multiple responsibilities.

## Layer 1: iOS device authentication

The local application uses device-owner authentication to determine whether the person holding the device may enter the app interface.

This is a local privacy control.

## Layer 2: Website authentication

The connected website remains responsible for sign-in state.

A user may unlock the app and still be required to sign in to the website.

## Layer 3: Server-side authorization

Server-side permissions remain responsible for deciding whether an authenticated user may access protected features such as label-dashboard functionality.

## Layer 4: Domain boundary

The app distinguishes known first-party hosts from external destinations.

This reduces the chance that arbitrary external pages are treated as if they were trusted application content.

## Layer 5: Session management

Users can explicitly clear website data stored inside the app.

This clears cookies and related WebKit website storage on the device.

## Layer 6: Background relocking

The native shell relocks when sent to the background.

This is separate from website logout and is intended to protect the local application view.

---

# Authentication and Session Behavior

The app currently uses the website's existing authentication flow rather than storing a private backend credential inside the iOS source code.

The expected behavior is:

1. User unlocks the native application using device authentication.
2. User opens a website-backed screen.
3. If the website has a valid session in the app's WebKit data store, that session may continue.
4. If no valid website session exists, the website asks the user to sign in.
5. Backend authorization determines what protected content becomes available.
6. The website session may remain in WebKit until it expires, is revoked, or the user clears website sessions from Settings.
7. Locking the app does not claim to invalidate the remote website session.

This separation is intentional.

A local device lock and a remote account session solve different problems.

---

# Accessibility

Accessibility is one of the core reasons this project exists in its current form.

The app is being developed with direct attention to **VoiceOver**, native iOS semantics, understandable controls, and non-visual usability.

## Native accessibility choices already present

The current application uses native SwiftUI controls wherever practical, including:

- `TabView`
- `NavigationStack`
- `List`
- `Form`
- `Button`
- `NavigationLink`
- `Label`
- `ProgressView`
- `ShareLink`
- Native confirmation dialogs
- Native alerts

Native controls generally provide a stronger accessibility baseline than custom-drawn controls.

## VoiceOver-aware details

Examples in the current code include:

- Decorative lock imagery hidden from accessibility when it would create redundant speech
- Important text marked with header traits
- Text-entry prompts given explicit accessibility labels
- Native labels used for toolbar controls
- Understandable button names instead of icon-only actions
- Spoken loading text
- Readable error messages
- Native confirmation dialogs for destructive behavior

## Dynamic Type

The SwiftUI shell uses system text styles and is intended to respect preferred text-size settings.

## Appearance

The app follows device appearance rather than forcing a custom visual theme that could conflict with accessibility preferences.

## Website accessibility

Website-backed screens depend on the accessibility of the pages loaded from `mrblindbandit.net` and its first-party services.

The app can provide a strong native shell, but a poorly structured web page would still affect VoiceOver users inside WKWebView.

For that reason, accessibility work on the website and accessibility work in the app are treated as connected responsibilities.

## Accessibility goals

The ongoing standard for this project is that core flows should be independently operable with VoiceOver.

That includes:

- Unlocking the app
- Changing tabs
- Opening website sections
- Navigating backward and forward
- Reloading a failed page
- Opening external links
- Clearing sessions
- Reaching account settings
- Understanding error states
- Understanding loading states
- Using website authentication flows

---

# Web Integration

The app uses `WKWebView` as the web-content surface for connected platform pages.

This creates several advantages:

- The website remains the central source of truth.
- Platform features can be updated server-side without duplicating every web page in Swift.
- Authentication state can remain tied to the website's existing system.
- Native app navigation can coexist with rapidly evolving web functionality.

## First-party trust model

The app currently treats the defined Mr. Blindbandit domains as first party.

First-party pages may remain inside the in-app browser.

External HTTPS URLs are opened through iOS instead.

This keeps the embedded browser focused on the Mr. Blindbandit platform rather than turning it into a general-purpose browser.

## Pop-up handling

When a first-party page attempts to open a new window, the app can load that request in the existing web view.

External HTTPS pop-ups are redirected to the system browser.

## Supported URL behavior

The navigation policy currently allows supported handling for:

- HTTPS
- `mailto:`
- `tel:`

Unsupported behavior is not silently trusted.

---

# Architecture

The current project is intentionally compact.

A simplified text view of the architecture is:

```text
+-----------------------------------------------------------+
|                    Mr. Blindbandit App                    |
|                                                           |
|  +---------------------+   +---------------------------+  |
|  | Native SwiftUI      |   | Device Security           |  |
|  |                     |   |                           |  |
|  | - Tabs              |   | - Face ID                |  |
|  | - Navigation        |   | - Touch ID               |  |
|  | - Settings          |   | - Passcode               |  |
|  | - Error UI          |   | - Background relock      |  |
|  +----------+----------+   +---------------------------+  |
|             |                                             |
|             v                                             |
|  +-----------------------------------------------------+  |
|  | WKWebView / Website Surface                         |  |
|  |                                                     |  |
|  | - mrblindbandit.net                                 |  |
|  | - account                                           |  |
|  | - media tools                                       |  |
|  | - community                                         |  |
|  | - label portal                                      |  |
|  +---------------------------+-------------------------+  |
+------------------------------|----------------------------+
                               |
                               v
+-----------------------------------------------------------+
|               Website / Server Authorization              |
|                                                           |
|   Authentication • Sessions • Roles • Protected APIs      |
+-----------------------------------------------------------+
```

The important architectural rule is that the native device-authentication layer and server authorization layer remain separate.

---

# Technology Stack

## Application

- **Swift**
- **SwiftUI**
- **WebKit / WKWebView**
- **LocalAuthentication**
- **UIKit interoperability** where required for alerts and application APIs

## Project generation

- **XcodeGen**
- `project.yml`

## Build tooling

- `xcodebuild`
- Shell script packaging
- `ditto`
- ZIP-based IPA packaging

## Continuous integration

- **GitHub Actions**
- macOS runner
- Xcode toolchain available on GitHub-hosted macOS runners

## Connected platform

- `mrblindbandit.net`
- First-party account and portal domains

---

# Repository Structure

```text
mr.-Blindbandit-app/
|
|-- App/
|   `-- BlindbanditApp.swift
|
|-- .github/
|   `-- workflows/
|       `-- ios.yml
|
|-- build-unsigned.sh
|-- project.yml
`-- README.md
```

## `App/BlindbanditApp.swift`

Contains the current native application implementation, including:

- App entry point
- Device lock logic
- Native tab navigation
- Home screen
- Settings screen
- WKWebView wrapper
- Browser navigation delegate
- Browser UI delegate
- Loading and failure handling
- First-party URL rules
- JavaScript dialog bridging

## `project.yml`

Defines the XcodeGen project configuration.

Current configuration includes:

- App name: `Blindbandit`
- iOS deployment target: `17.0`
- Swift version: `5.0`
- Product bundle identifier: `net.mrblindbandit.privateapp`
- Generated Info.plist
- Face ID usage description
- iPhone and iPad targeted device families
- Marketing version `1.0`
- Build version `1`
- Code signing disabled for the repository's unsigned-build flow

## `build-unsigned.sh`

Creates the Xcode project, builds the Release application for a generic iOS device, creates an IPA payload directory, and packages the `.app` into an unsigned IPA.

## `.github/workflows/ios.yml`

Builds the unsigned IPA automatically on GitHub-hosted macOS infrastructure.

---

# Requirements

For local development or local unsigned builds, use a Mac with:

- macOS capable of running a compatible Xcode version
- Xcode
- Xcode command-line tools
- XcodeGen
- Git
- Internet access for connected website features

The application currently targets:

- **iOS 17.0 or later**

The Xcode project configuration targets both iPhone and iPad device families, although the application experience should be tested separately on each form factor.

---

# Local Development

## 1. Clone the repository

```bash
git clone https://github.com/mrblindbandit/mr.-Blindbandit-app.git
cd mr.-Blindbandit-app
```

## 2. Install XcodeGen

If Homebrew is installed:

```bash
brew install xcodegen
```

## 3. Generate the Xcode project

```bash
xcodegen generate
```

This creates:

```text
Blindbandit.xcodeproj
```

## 4. Open the project

```bash
open Blindbandit.xcodeproj
```

## 5. Select a simulator or development device

For development and debugging, choose an available iOS simulator or a properly configured physical device.

The repository's default project configuration disables code signing for the automated unsigned-build process, so normal on-device development may require changing signing settings locally.

---

# Building an Unsigned IPA

The repository contains a build helper:

```bash
bash build-unsigned.sh
```

The script performs the following steps:

1. Verifies that `xcodebuild` is available.
2. Verifies that `xcodegen` is available.
3. Generates the Xcode project.
4. Builds the Release target for generic iOS hardware.
5. Disables signing requirements for the build.
6. Verifies the generated app executable exists.
7. Creates a `Payload` directory.
8. Copies `Blindbandit.app` into the IPA payload structure.
9. Creates `Blindbandit-unsigned.ipa`.

Expected output:

```text
build/Blindbandit-unsigned.ipa
```

## Important

An unsigned IPA is **not equivalent to an App Store-signed application**.

It must still be signed or installed using an appropriate method compatible with the target device and Apple's platform rules.

This repository does not store private Apple signing certificates or provisioning profiles.

---

# GitHub Actions

The project includes an automated GitHub Actions workflow:

```text
.github/workflows/ios.yml
```

## Triggers

The workflow currently runs:

- On pushes to `main`
- Manually through `workflow_dispatch`

## Runner

The build currently uses:

```text
macos-15
```

## Workflow steps

The workflow:

1. Checks out the repository.
2. Installs XcodeGen using Homebrew.
3. Runs `build-unsigned.sh`.
4. Uploads the resulting unsigned IPA as a GitHub Actions artifact.

## Artifact name

```text
Blindbandit-unsigned-IPA
```

## Artifact retention

The current workflow requests a retention period of:

```text
7 days
```

## Why use CI for this project?

Automated builds provide several benefits:

- Reproducible build steps
- A clear record of build failures
- Easier testing after repository changes
- No need to manually package an IPA every time
- A convenient source of test artifacts

---

# Installing an Unsigned Build

The output generated by this repository is intentionally unsigned.

Before installation on a physical iPhone or iPad, it must be signed using a legitimate method supported by the install workflow being used.

Possible testing workflows may include personal development signing or compatible sideloading tools, depending on the user's Apple account, device, certificates, provisioning state, and current Apple requirements.

This README intentionally does not embed certificates, private keys, provisioning profiles, or account credentials.

---

# Configuration

Most current application behavior is defined directly in the Swift source and `project.yml`.

Important current values include:

## Website base URL

```text
https://mrblindbandit.net
```

## Bundle identifier

```text
net.mrblindbandit.privateapp
```

## Minimum iOS version

```text
17.0
```

## First-party hosts

The embedded browser currently recognizes specific Mr. Blindbandit domains as first party.

When adding or changing a first-party service, update the domain allowlist carefully rather than broadly treating arbitrary URLs as trusted.

---

# Privacy

The app is designed to minimize unnecessary local complexity while still allowing website-backed account sessions.

## Local data currently used

The native app uses local state for behavior such as whether secure unlock has been configured.

The embedded website may use its own cookies and browser storage inside WKWebView according to the website's authentication and application requirements.

## Website sessions

The app provides a user-facing control to clear website session data stored by WKWebView.

That action clears website data in the app on the current device.

It does not claim to erase remote account data or sign the user out of unrelated devices.

## Server secrets

The project architecture is designed so private server secrets should not need to be bundled in the client application.

Public client identifiers may be appropriate for some services, but reusable private backend secrets belong on protected server infrastructure rather than in a public repository or mobile application binary.

---

# Security Boundaries

A professional security model requires being clear about what each mechanism does and does not protect.

## Device authentication protects

- Entry into the native app interface on the current device
- Casual access after the app has been backgrounded
- Private app content from immediate exposure without device-owner authentication

## Device authentication does not automatically protect

- Remote website sessions on other devices
- The user's email account
- The user's GitHub account
- Backend APIs if they are incorrectly authorized
- Server-side data from an already compromised server account

## Website authentication protects

- Website identity and session state

## Server authorization protects

- Which authenticated identities are allowed to perform protected actions

## Domain restrictions protect

- The in-app browser from casually treating arbitrary external sites as first-party app content

## Session clearing protects

- Stored website cookies and browser data inside the app after the user explicitly clears them

Good security comes from the combination of these layers, not from pretending one layer solves every problem.

---

# Testing Strategy

The project should be tested from several perspectives.

## Functional testing

Verify that:

- The app launches correctly.
- Secure unlock can be configured.
- Successful authentication opens the app.
- Failed or cancelled authentication leaves the app locked.
- Backgrounding relocks the app.
- Each tab opens the correct destination.
- Back and Forward update correctly.
- Reload works.
- Open in Safari opens the current URL.
- External links leave the embedded first-party context as intended.
- First-party links remain available inside the app.
- Session clearing removes app browser data.
- The app remains usable after sessions are cleared.
- Network failure shows a readable recovery path.

## Authentication testing

Test:

- No website session
- Valid website session
- Expired website session
- Revoked website session
- Manual website logout
- App background lock while website session remains valid
- Session clearing from Settings
- Reauthentication after session clearing

## Network testing

Test under:

- Wi-Fi
- Cellular
- Slow network
- Interrupted network
- Temporary offline state
- Server error state
- Web content process restart

## Navigation testing

Test:

- Deep first-party navigation
- Back stack
- Forward stack
- External HTTPS links
- `mailto:` links
- `tel:` links
- Pop-up behavior
- Website redirects

## Device testing

Where possible, test:

- Face ID device
- Touch ID device
- Passcode-only fallback
- iPhone
- iPad
- Multiple text sizes
- Light mode
- Dark mode

---

# Accessibility Testing Checklist

Every meaningful release should be checked with VoiceOver enabled.

## App launch and lock screen

- [ ] Lock-screen title is announced correctly.
- [ ] Decorative imagery does not create unnecessary speech.
- [ ] Unlock button is clearly named.
- [ ] Busy state is understandable.
- [ ] Authentication failure message is readable.

## Tabs

- [ ] All four tabs have meaningful names.
- [ ] Selected-tab state is understandable.
- [ ] VoiceOver order is predictable.

## Home

- [ ] Main heading is announced as a heading.
- [ ] Website shortcuts have meaningful names.
- [ ] Label shortcuts are understandable.
- [ ] Share action is operable.

## Website surface

- [ ] Loading state is announced.
- [ ] Failure state can be discovered.
- [ ] Retry button is operable.
- [ ] Back and Forward controls have meaningful labels.
- [ ] Reload has a meaningful label.
- [ ] Open in Safari has a meaningful label.
- [ ] Web content itself remains usable with VoiceOver.

## Dialogs

- [ ] Alert content is spoken.
- [ ] Confirm and Cancel are clearly identified.
- [ ] Text input prompt has an accessible label.

## Settings

- [ ] Security section is understandable.
- [ ] Destructive session-clearing action is clearly named.
- [ ] Confirmation dialog explains consequences.
- [ ] Account settings navigation is reachable.

## Dynamic Type

- [ ] Content remains usable at larger text sizes.
- [ ] Controls do not become impossible to operate.

---

# Beta Testing

This project is well suited to structured private beta testing because it combines native UI, device authentication, web sessions, website permissions, accessibility, and multiple navigation boundaries.

## Ideal beta testers

Useful testers include people who can evaluate one or more of the following:

- VoiceOver accessibility
- iOS navigation
- Face ID / Touch ID behavior
- Session persistence
- Authentication flows
- WebView behavior
- External link handling
- Creator workflows
- Label portal access
- Network failure behavior
- iPad layout
- Dynamic Type
- Security UX

## What beta testers should report

A strong report should include:

- Device model
- iOS version
- App build or commit
- Whether VoiceOver was enabled
- Network type
- Starting state
- Exact steps to reproduce
- Expected behavior
- Actual behavior
- Whether the problem is repeatable
- Screenshots or recordings when appropriate
- Accessibility impact
- Severity

## Accessibility beta reports

For VoiceOver issues, include:

- The control or page involved
- What VoiceOver announces
- What should be announced
- Whether focus becomes trapped or lost
- Whether the action can still be completed non-visually
- Whether there is a workaround

## Security-related beta reports

Do not post sensitive security findings publicly if disclosure could create real risk.

See [Responsible Security Reporting](#responsible-security-reporting).

---

# Bug Reports

Before reporting a bug, try to determine whether it belongs to:

1. The native iOS shell
2. WKWebView behavior
3. The website
4. Authentication
5. Backend permissions
6. Network conditions
7. Accessibility

A useful issue title might look like:

```text
[Accessibility] VoiceOver focus is lost after clearing website sessions
```

or:

```text
[Navigation] External account link remains inside WKWebView unexpectedly
```

A good bug report answers four questions:

1. **What did you do?**
2. **What did you expect?**
3. **What actually happened?**
4. **Can someone else reproduce it?**

---

# Troubleshooting

## `xcodegen: command not found`

Install XcodeGen:

```bash
brew install xcodegen
```

## `xcodebuild: command not found`

Install Xcode and ensure command-line tools are configured.

You may need to verify the active developer directory:

```bash
xcode-select -p
```

## The build succeeds but the IPA will not install

The generated IPA is unsigned.

A valid signing and provisioning method is still required for installation on iOS hardware.

## The website does not load

Check:

- Internet connection
- Whether `mrblindbandit.net` is reachable
- Whether the current website route exists
- Whether authentication is required
- Whether the website returned an error

Use the in-app retry control after restoring connectivity.

## The label dashboard opens but access is denied

That can be correct behavior.

Unlocking the native app does not grant label permissions. Access remains subject to website authentication and server-side authorization.

## Face ID is unavailable

Confirm Face ID, Touch ID, or a device passcode is configured on the iPhone or iPad.

The app uses device-owner authentication rather than implementing a separate biometric database.

## Website login keeps returning

Possible causes include:

- Session expiration
- Server-side revocation
- Cleared WebKit website data
- Authentication-provider changes
- Cookie or storage behavior

Reauthenticate through the website flow.

---

# Roadmap

The app is intentionally capable of evolving beyond the current web-connected companion model.

Potential future directions include:

## Native platform features

- More native account surfaces
- Native notifications
- Native media previews
- Native upload flows
- Native creator shortcuts
- Native dashboard summaries
- Native settings synchronization

## Accessibility improvements

- Continued VoiceOver regression testing
- Improved focus restoration around web/native transitions
- More accessibility announcements for important state changes
- Larger Dynamic Type verification matrix
- Better accessibility documentation for beta testers

## Security improvements

- Additional session-state visibility
- More explicit reauthentication for high-risk actions where appropriate
- Better security-event messaging
- Expanded testing around role boundaries and expired sessions
- Review of first-party URL boundaries as services change

## Creator features

- Media-tool shortcuts
- Audio workflow integrations
- Upload status
- Creator utilities
- Publishing shortcuts
- Release management surfaces where appropriate

## Platform integration

- Deeper first-party API integrations where they improve the experience
- Reduced dependence on embedded web pages for workflows that benefit significantly from native UI
- Better offline behavior for appropriate content

## Build and release engineering

- More automated validation
- Build metadata
- Version tagging
- Release notes
- Optional signed-distribution workflows kept separate from public secrets

The roadmap is directional rather than a promise of specific release dates.

---

# Development Philosophy

This project is built around a simple idea:

**Accessibility, security, and usefulness should reinforce each other.**

An app should not become inaccessible because security was added badly.

An app should not become insecure because login convenience was prioritized over authorization boundaries.

A creator tool should not require a giant engineering organization to remain useful.

The Mr. Blindbandit App is being developed as a practical bridge between a growing web platform and a native iOS experience.

That means:

- Keep sensitive authority on the server.
- Keep native controls native where possible.
- Keep first-party trust boundaries explicit.
- Keep error states understandable.
- Keep accessibility testable.
- Keep the app small enough to reason about.
- Expand native functionality where it creates real value.

---

# Responsible Security Reporting

Security research and testing should be performed responsibly.

If you discover a vulnerability that could expose private information, bypass authorization, compromise accounts, disclose credentials, or create material risk:

- Do not exploit the issue beyond what is necessary to verify it.
- Do not access other users' private data.
- Do not publish sensitive reproduction details before the issue can be addressed.
- Record the minimum information needed to reproduce the problem.
- Report the issue privately through an appropriate Mr. Blindbandit contact channel.

A useful security report should include:

- Affected component
- Preconditions
- Reproduction steps
- Expected security boundary
- Actual behavior
- Potential impact
- Whether user interaction is required
- Whether authentication is required
- Suggested mitigation, if known

---

# About Mr. Blindbandit

**Mr. Blindbandit** is an independent artist, producer, creator, and technology builder working across music, accessibility, creator tools, AI-assisted development, web platforms, and mobile applications.

The broader project is focused on building a creator-owned ecosystem where music and technology work together instead of living in disconnected silos.

Accessibility is central to that mission.

The project is being developed from the perspective of a blind creator who uses assistive technology directly and understands how quickly a technically functional product can become unusable when accessibility is ignored.

The larger Mr. Blindbandit ecosystem includes work around:

- Music and artist experiences
- Creator media tools
- Audio workflows
- Art track generation
- Audiograms
- Artwork utilities
- Website publishing
- Accounts and authentication
- Label operations
- Community features
- Mobile experiences
- Accessibility-first product design
- AI-assisted development and automation

## Official website

**https://mrblindbandit.net**

## GitHub profile

**https://github.com/mrblindbandit**

---

<div align="center">

# Build it useful. Build it secure. Build it accessible.

### Mr. Blindbandit

**Music • Technology • Accessibility • Creator Independence**

</div>
