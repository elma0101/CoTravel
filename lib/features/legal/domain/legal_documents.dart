/// Changing this asks every user to accept the terms again.
const currentTermsVersion = '2026-11-draft';

/// Shown on every document until a lawyer has reviewed the text.
const legalDocumentsAreDraft = true;

class LegalSection {
  const LegalSection(this.heading, this.body);

  final String heading;
  final String body;
}

class LegalDocument {
  const LegalDocument({required this.title, required this.sections});

  final String title;
  final List<LegalSection> sections;
}

const termsOfUse = LegalDocument(
  title: 'Terms of use',
  sections: [
    LegalSection(
      'What CoTravel is',
      'CoTravel is a software tool that helps people find each other and coordinate trips they organize themselves. CoTravel is not a travel agency or tour operator. It does not sell, organize, or guarantee trips, transport, or lodging, and it does not handle payments.',
    ),
    LegalSection(
      'Your responsibility',
      'You decide who you travel with and which plans you join. You are responsible for your own safety, documents, insurance, and any arrangements and costs you agree with other travelers. Members are not employees or representatives of CoTravel.',
    ),
    LegalSection(
      'Verification has limits',
      'A LinkedIn check confirms only that an account is linked to a LinkedIn profile. Occupation and Instagram details are declared by members and are not checked. None of this guarantees who someone is or how they will behave.',
    ),
    LegalSection(
      'Acceptable use',
      'Be honest in your profile and trip listings. Do not harass, threaten, or defraud anyone, and do not sell commercial travel services. We may remove content or suspend accounts that break these rules.',
    ),
    LegalSection(
      'Leaving and cancelling',
      'Travelers can leave without a late mark until 7 days before departure. Leaving after that is recorded and the host is told. CoTravel takes no payments, so any refund or shared cost is between travelers.',
    ),
    LegalSection(
      'Your account',
      'You can delete your account from your profile at any time. Hosts must first cancel upcoming trips that have confirmed travelers.',
    ),
  ],
);

const privacyPolicy = LegalDocument(
  title: 'Privacy policy',
  sections: [
    LegalSection(
      'What we collect',
      'Your email address, your profile details and photo, whether a LinkedIn account is linked, the trips you create and save and the photos you add to them, your requests and the details you declare in them, your group chat messages, your safety reports and blocks, your notification device token, basic usage events, and crash reports that are not linked to your account.',
    ),
    LegalSection(
      'Who can see it',
      'Other signed-in members can see your profile and your trips. Group members can see the group chat. Hosts can see the introduction you send with a request. Members you block, and members who block you, cannot see your profile.',
    ),
    LegalSection(
      'Services we use',
      'Data is stored with Supabase. Push notifications are delivered through Firebase Cloud Messaging. Linking LinkedIn shares basic identity details from LinkedIn with us.',
    ),
    LegalSection(
      'Deleting your account',
      'Deleting your account removes your profile, photo, requests, blocks, and the trips you created with their photos. Messages you sent remain visible to their group under the name "Former member". Safety reports are kept without your account linked, so that complaints cannot be erased.',
    ),
  ],
);
