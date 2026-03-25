# T12.3 Metadata Pack (App Store Connect + Alcohol Wording)

This pack contains release-prep drafts for `T12.3`:
- App Store Connect metadata copy
- Screenshot checklist
- Alcohol-policy wording suitable for App Review notes / questionnaire answers
- Age-rating / content questionnaire answers (draft)
- Privacy policy draft (host externally; link from App Store Connect)

## Truth sources used (consistency)
- In-app age-gate UI text (21+): `OnboardingAgeConfirmationView`
  - "Bcup is only available to users aged 21 and older..."
  - Button: "I am 21 or older"
- Onboarding gating: home is not accessible until `profiles/{uid}.onboardingCompleteAt` is set.
- Product positioning: private, invite-only drinking-game communities with social game logging + required photo evidence.

## What you must fill in App Store Connect (field-by-field checklist)
Fill these fields using the drafts in this folder.

### 1) General metadata
- App Name: (use your App Store Connect value; keep consistent with in-app "Bcup")
- Subtitle: use `app-copy-v1.md`
- App Description: use `app-copy-v1.md`
- Keywords: use `app-copy-v1.md`
- Category: choose best fit (you decide; drafts assume a games / social category)
- Primary Language: set to match your copy

### 2) App URL fields
- Support URL: set to your support/FAQ page (draft URL placeholder in `privacy-policy-draft.md`)
- Privacy Policy URL: set to your hosted privacy policy page (see `privacy-policy-draft.md`)

### 3) App Store screenshots
- Use `screenshot-checklist.md` as the required coverage list.

### 4) App Review "Notes"
- Paste / adapt `alcohol-policy-wording.md` (sectioned copy so reviewers can verify age gating).

### 5) Age rating / content questionnaire
- Use `age-rating-questionnaire-answers.md` as the draft answer set.

### 6) Compliance linkage you must verify before submission
- Confirm your hosted privacy policy URL is reachable without login.
- Confirm support URL is reachable.
- Confirm your alcohol-related questionnaire answers match the same wording logic as in-app gating.

## Draft artifacts included
- `app-copy-v1.md`
- `screenshot-checklist.md`
- `alcohol-policy-wording.md`
- `age-rating-questionnaire-answers.md`
- `privacy-policy-draft.md`

## Notes
- These drafts are written to match your current V1 behavior; have a qualified reviewer/legal counsel confirm any wording decisions for App Review.
- I cannot directly access or fill App Store Connect on your behalf; you will paste/link the drafts.

