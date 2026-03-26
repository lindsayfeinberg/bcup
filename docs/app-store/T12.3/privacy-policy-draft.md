# Privacy Policy (Draft for App Store Connect) - Bcup

This is a draft for release-prep. Please have qualified legal counsel review it before publishing.

## Effective Date
(Insert effective date, e.g. March 25, 2026)

## 1. Overview
This Privacy Policy explains how `Bcup` ("we", "us", or "our") collects, uses, and shares information when you use our iOS app.

## 2. Who we are
App name: `Bcup`
Contact: mayastester@gmail.com
Support URL: https://<your-github-pages-domain>/support

## 3. Information we collect
### 3.1 Account and identity information
We use Firebase Authentication with Google Sign-In. When you sign in, we receive authentication identifiers provided by Google/Firebase.

### 3.1.1 Device and usage information
We may collect information about how the app is used and information about your device (for example, crash logs and basic usage analytics) through Firebase Analytics and Crashlytics.

### 3.2 Profile information you provide
After you confirm you are 21+ during onboarding, you can create or update your profile. We store:
- Display name
- Profile photo URL (from your uploaded image)

We also store onboarding status used for access control:
- Whether you have confirmed you are 21+ (`ageConfirmed21PlusAt`)
- Whether onboarding is complete (`onboardingCompleteAt`)

### 3.3 User-generated content (photos and game logs)
`Bcup` is built around private, invite-only drinking-game communities where users can log game outcomes with required photo evidence.

When you create a game log, you may upload one or more photos. We store:
- Photo URLs for each uploaded image (in Firebase Storage)
- Game log details and associated outcomes (stored in Cloud Firestore), including community membership context and other game-related fields.

Access to community content is limited to members of each private community.

## 4. How we use information
We use the information described above to:
- Provide access to the app (including 21+ eligibility gating)
- Create and manage user profiles
- Enable invite-only communities and membership access
- Allow users to log game outcomes and display community activity
- Compute and display odds and bracket information
- Provide app functionality and improve stability using analytics and crash reporting

## 5. Where information is stored
We store information in Google/Firebase services, including:
- Cloud Firestore (for profiles and game log data)
- Firebase Storage (for uploaded photos)

## 6. Third-party services
We use the following third-party services:
- Google Sign-In (authentication)
- Firebase (Cloud Firestore, Firebase Storage, Cloud Functions as backend logic)
- Firebase Analytics and Crashlytics (usage analytics and crash reporting)

## 7. How we share information
We share information as needed to provide the app experience, including:
- Sharing your logged game outcomes and associated photos within the private community(s) you are a member of.
- Sharing data with Firebase/Google service providers to run the app infrastructure and analytics/crash reporting.

We do not sell your personal information for monetary consideration.

## 8. Data retention
We retain information as long as needed to provide the app, maintain functionality, and comply with legal requirements. If you delete your account or data, we will handle deletion in accordance with our system capabilities.

## 9. Your choices and access
You can review and update certain profile information in the app.
If you need help with privacy-related requests, contact us using the support contact listed in Section 2.

## 10. Children and underage users
`Bcup` is intended for users aged 21 and older. During onboarding, users must self-confirm they are 21+ before accessing the app.

## 11. Security
We use administrative and technical controls designed to protect information. However, no method of transmission or storage is 100% secure.

## 12. Changes to this Privacy Policy
We may update this Privacy Policy from time to time. If we make material changes, we will update the effective date.

## 13. Contact us
Email: mayastester@gmail.com
Privacy requests: https://<your-github-pages-domain>/privacy

