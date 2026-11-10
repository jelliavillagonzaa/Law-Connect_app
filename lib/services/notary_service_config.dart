import 'package:cloud_firestore/cloud_firestore.dart';

class NotaryDocumentItem {
  final String? id;
  final String title;
  final String category;
  final String description;
  final String example;
  final List<String> requiredDocuments;
  final Map<String, String> documentHints;
  final String copiesRecommended;
  final String importantNote;
  final String whoMustAppear;
  final String? estimatedFee;
  final String? sampleImageUrl;
  final String? sampleAssetPath;
  final String? sampleTemplateText;
  final bool isCustom;
  final DateTime? createdAt;

  const NotaryDocumentItem({
    this.id,
    required this.title,
    required this.category,
    required this.description,
    required this.example,
    required this.requiredDocuments,
    this.documentHints = const {},
    this.copiesRecommended =
        '3 to 4 original printed sets (1 for Client, 1 for Notarial Register, 1-2 for Agency/Registry).',
    this.importantNote =
        'CRITICAL: DO NOT sign this document beforehand! You must sign in the presence of the Notary Public with valid photo identification.',
    this.whoMustAppear =
        'All signing parties / affiants must personally appear with original valid IDs.',
    this.estimatedFee,
    this.sampleImageUrl,
    this.sampleAssetPath,
    this.sampleTemplateText,
    this.isCustom = false,
    this.createdAt,
  });

  /// Returns the image URL or local asset path for this document
  String get resolvedDocumentImage {
    if (sampleImageUrl != null && sampleImageUrl!.trim().isNotEmpty) {
      return sampleImageUrl!.trim();
    }
    if (sampleAssetPath != null && sampleAssetPath!.trim().isNotEmpty) {
      return sampleAssetPath!.trim();
    }
    final lower = title.toLowerCase();
    if (lower.contains('loss')) return 'assets/notary/affidavit_of_loss.jpg';
    if (lower.contains('joint') || lower.contains('disinterested')) {
      return 'assets/notary/joint_affidavit.jpg';
    }
    if (lower.contains('spa') || lower.contains('power of attorney')) {
      return 'assets/notary/special_power_of_attorney.jpg';
    }
    if (lower.contains('sale') || lower.contains('deed') || lower.contains('donation') || lower.contains('contract') || lower.contains('lease')) {
      return 'assets/notary/deed_of_sale.jpg';
    }
    return 'assets/notary/joint_affidavit.jpg';
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'category': category,
      'description': description,
      'example': example,
      'requiredDocuments': requiredDocuments,
      'documentHints': documentHints,
      'copiesRecommended': copiesRecommended,
      'importantNote': importantNote,
      'whoMustAppear': whoMustAppear,
      'estimatedFee': estimatedFee,
      'sampleImageUrl': sampleImageUrl,
      'sampleTemplateText': sampleTemplateText,
      'isCustom': true,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
    };
  }

  factory NotaryDocumentItem.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return NotaryDocumentItem(
      id: doc.id,
      title: data['title']?.toString() ?? '',
      category: data['category']?.toString() ?? 'General Notarization',
      description: data['description']?.toString() ?? '',
      example: data['example']?.toString() ?? '',
      requiredDocuments: List<String>.from(data['requiredDocuments'] ?? []),
      documentHints: Map<String, String>.from(data['documentHints'] ?? {}),
      copiesRecommended: data['copiesRecommended']?.toString() ??
          '3 to 4 original printed sets (1 for Client, 1 for Notarial Register, 1-2 for Agency/Registry).',
      importantNote: data['importantNote']?.toString() ??
          'CRITICAL: DO NOT sign this document beforehand! You must sign in the presence of the Notary Public with valid photo identification.',
      whoMustAppear: data['whoMustAppear']?.toString() ??
          'All signing parties / affiants must personally appear with original valid IDs.',
      estimatedFee: data['estimatedFee']?.toString(),
      sampleImageUrl: data['sampleImageUrl']?.toString(),
      sampleTemplateText: data['sampleTemplateText']?.toString(),
      isCustom: true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class NotaryServiceConfig {
  static const String officeHours = 'Monday to Friday • 8:00 AM – 5:00 PM';
  static const String walkInAdvisory =
      'Notarial services are strictly walk-in (first-come, first-served). No advance booking required. Please ensure all signers are personally present with valid photo IDs and unsigned documents.';

  static const List<String> acceptedValidIds = [
    'Philippine National ID (PhilID / ePhilID)',
    'Driver’s License (LTO)',
    'Philippine Passport (DFA)',
    'UMID (SSS / GSIS)',
    'PRC Professional Identification Card',
    'Postal ID (Digitized PVC)',
    'Voter’s Certification (with biometric photo)',
    'Senior Citizen ID',
    'OWWA / OFW Identification Card',
    'Police Clearance ID (with photo and signature)',
  ];

  static const List<NotaryDocumentItem> documents = [
    NotaryDocumentItem(
      title: 'Affidavit of Loss',
      category: 'Affidavits',
      sampleAssetPath: 'assets/notary/affidavit_of_loss.jpg',
      description:
          'A sworn statement that an official ID, card, certificate, or property paper was lost and cannot be retrieved after diligent search.',
      example:
          'You lost your PhilID, driver’s license, passport, diploma, or ATM card, and the issuing agency (LTO, DFA, PSA, or bank) requires a notarized Affidavit of Loss.',
      requiredDocuments: [
        'Valid Government-issued Photo ID',
        'Unsigned Affidavit of Loss (at least 3 copies)',
        'Photocopy of lost document (if previously saved)',
        'Police Report / Blotter (if loss involves theft or crime)',
      ],
      documentHints: {
        'Valid Government-issued Photo ID':
            'Bring original PhilID, driver\'s license, or passport.',
        'Unsigned Affidavit of Loss (at least 3 copies)':
            'Bring printed copies. Do not sign yet.',
        'Photocopy of lost document (if previously saved)':
            'Helps verify the exact ID or account number.',
        'Police Report / Blotter (if loss involves theft or crime)':
            'Required by some agencies if the document was stolen.',
      },
      whoMustAppear: 'The affiant (the owner of the lost item) must personally appear.',
    ),
    NotaryDocumentItem(
      title: 'Joint Affidavit of Two Disinterested Persons',
      category: 'Affidavits',
      sampleAssetPath: 'assets/notary/joint_affidavit.jpg',
      description:
          'A sworn affidavit executed by two neutral individuals who personally know your birth details, name discrepancy, or civil status.',
      example:
          'Your PSA birth certificate has a discrepancy in your first name, date of birth, or late registration, and PSA or the Local Civil Registrar requires two independent witnesses.',
      requiredDocuments: [
        '2 Disinterested Witnesses (Non-relatives)',
        'Original Valid IDs of both witnesses',
        'Copy of Birth Certificate or Document with discrepancy',
        'Unsigned Joint Affidavit (at least 3 copies)',
      ],
      documentHints: {
        '2 Disinterested Witnesses (Non-relatives)':
            'Must be acquaintances/neighbors with no direct financial interest.',
        'Original Valid IDs of both witnesses':
            'Government photo IDs with signature.',
        'Copy of Birth Certificate or Document with discrepancy':
            'Shows the spelling or date discrepancy being clarified.',
        'Unsigned Joint Affidavit (at least 3 copies)':
            'To be signed by both witnesses before the notary.',
      },
      whoMustAppear: 'Both disinterested witnesses must personally appear before the notary.',
    ),
    NotaryDocumentItem(
      title: 'Special Power of Attorney (SPA)',
      category: 'Authorizations & SPA',
      sampleAssetPath: 'assets/notary/special_power_of_attorney.jpg',
      description:
          'Grants specific legal authority to another person to act, transact, sign, or collect documents on your behalf.',
      example:
          'You cannot go in person and need a relative or friend to claim your land title, process bank transactions, or represent you before government offices.',
      requiredDocuments: [
        'Principal (Grantor) Personal Appearance',
        'Valid Government IDs of Principal and Attorney-in-Fact',
        'Community Tax Certificate (Cedula)',
        'Unsigned SPA Document (at least 3 copies)',
        'Supporting proof (Title number, account info, or claim slip)',
      ],
      documentHints: {
        'Principal (Grantor) Personal Appearance':
            'The person giving the power MUST appear personally.',
        'Valid Government IDs of Principal and Attorney-in-Fact':
            'Original IDs with clear photos and specimen signatures.',
        'Community Tax Certificate (Cedula)':
            'Current year cedula of the principal.',
        'Unsigned SPA Document (at least 3 copies)':
            'Contains the specific authorized acts.',
        'Supporting proof (Title number, account info, or claim slip)':
            'Helps ensure details and account numbers are accurate.',
      },
      whoMustAppear: 'The Principal (grantor of authority) must appear personally.',
    ),
    NotaryDocumentItem(
      title: 'General Power of Attorney',
      category: 'Authorizations & SPA',
      sampleAssetPath: 'assets/notary/special_power_of_attorney.jpg',
      description:
          'Grants general administration authority to a designated agent to manage your legal affairs, businesses, and properties.',
      example:
          'You are traveling overseas or temporarily incapacitated and need a spouse or trusted representative to administer several ongoing financial or property matters.',
      requiredDocuments: [
        'Principal (Grantor) Personal Appearance',
        'Valid Government IDs of Principal and Agent',
        'Community Tax Certificate (Cedula)',
        'Unsigned General POA Document (at least 3 copies)',
      ],
      documentHints: {
        'Principal (Grantor) Personal Appearance':
            'Must appear in person with sound mind.',
        'Valid Government IDs of Principal and Agent':
            'Original IDs with photo and signature.',
        'Community Tax Certificate (Cedula)':
            'Latest cedula of the principal.',
        'Unsigned General POA Document (at least 3 copies)':
            'Printed unsigned document.',
      },
      whoMustAppear: 'The Principal must personally appear.',
    ),
    NotaryDocumentItem(
      title: 'Deed of Absolute Sale (Real Property / Land)',
      category: 'Deeds & Property',
      sampleAssetPath: 'assets/notary/deed_of_sale.jpg',
      description:
          'The official legal deed transferring ownership of titled land, a house, or a condo from seller to buyer.',
      example:
          'You are buying or selling a parcel of land in Misamis Occidental and need the notarized deed to pay capital gains tax and register the transfer at the Registry of Deeds.',
      requiredDocuments: [
        'All Sellers & Buyers (plus Spouses if married)',
        '2 Valid Government IDs of all parties',
        'Original & Photocopy of Transfer Certificate of Title (TCT) / OCT',
        'Latest Tax Declaration (Land & Improvement)',
        'Latest Real Property Tax (RPT) Official Receipt',
        'Cedula (Community Tax Certificate) of all parties',
        'Unsigned Deed of Absolute Sale (at least 5 copies)',
      ],
      documentHints: {
        'All Sellers & Buyers (plus Spouses if married)':
            'Spouses must appear and sign conformity if conjugal property.',
        '2 Valid Government IDs of all parties':
            'Original photo IDs with signatures.',
        'Original & Photocopy of Transfer Certificate of Title (TCT) / OCT':
            'Issued by the Registry of Deeds.',
        'Latest Tax Declaration (Land & Improvement)':
            'From the City/Municipal Assessor.',
        'Latest Real Property Tax (RPT) Official Receipt':
            'From the City/Municipal Treasurer.',
        'Cedula (Community Tax Certificate) of all parties':
            'Current year CTC.',
        'Unsigned Deed of Absolute Sale (at least 5 copies)':
            '1 for Notary, 1 for RD, 1 for BIR, 1 for Buyer, 1 for Seller.',
      },
      copiesRecommended:
          'At least 5 original sets (Notarial Book, BIR Car, Registry of Deeds, Buyer, Seller).',
      importantNote:
          'CRITICAL: If the seller is married, the spouse MUST also sign. Bring 2 valid IDs per party.',
      whoMustAppear: 'Both Seller(s) and Buyer(s), including spouses, must appear personally.',
    ),
    NotaryDocumentItem(
      title: 'Deed of Absolute Sale (Motor Vehicle)',
      category: 'Deeds & Property',
      sampleAssetPath: 'assets/notary/deed_of_sale.jpg',
      description:
          'The notarized deed recording the sale and ownership transfer of a motorcycle, car, van, or truck.',
      example:
          'You bought or sold a second-hand motorcycle or car and need to process the change of ownership at the LTO.',
      requiredDocuments: [
        'Seller and Buyer Personal Appearance',
        '2 Valid Government IDs each (with 3 specimen signatures on photocopy)',
        'Original LTO Official Receipt (OR) and Certificate of Registration (CR)',
        'Unsigned Deed of Sale of Motor Vehicle (at least 4 copies)',
        'Secretary’s Certificate (if seller is a registered business/company)',
      ],
      documentHints: {
        'Seller and Buyer Personal Appearance':
            'Both parties must be present.',
        '2 Valid Government IDs each (with 3 specimen signatures on photocopy)':
            'LTO strictly inspects specimen signatures on ID copies.',
        'Original LTO Official Receipt (OR) and Certificate of Registration (CR)':
            'Must be verified against the motor and chassis numbers.',
        'Unsigned Deed of Sale of Motor Vehicle (at least 4 copies)':
            '1 for Notary, 1 for LTO, 1 for Buyer, 1 for Seller.',
        'Secretary’s Certificate (if seller is a registered business/company)':
            'Authorizing the signatory if vehicle is under company name.',
      },
      copiesRecommended: 'At least 4 copies (1 Notary, 1 LTO, 1 Buyer, 1 Seller).',
      whoMustAppear: 'Both the registered owner (seller) and buyer must appear personally.',
    ),
    NotaryDocumentItem(
      title: 'Deed of Donation',
      category: 'Deeds & Property',
      sampleAssetPath: 'assets/notary/deed_of_sale.jpg',
      description:
          'A notarized deed where an owner gratuitously gives property or land to a relative, child, or recipient.',
      example:
          'Parents voluntarily giving a portion of ancestral land or residential lot to their son or daughter as a gift.',
      requiredDocuments: [
        'Donor(s) and Donee(s) Personal Appearance',
        'Valid Government IDs of Donor and Donee',
        'Title or Tax Declaration of the donated property',
        'Latest Real Property Tax Receipt (Tax Clearance)',
        'Unsigned Deed of Donation (at least 5 copies)',
      ],
      documentHints: {
        'Donor(s) and Donee(s) Personal Appearance':
            'The donee must also sign accepting the donation.',
        'Valid Government IDs of Donor and Donee':
            'With photo and signature.',
        'Title or Tax Declaration of the donated property':
            'Proof of ownership of the donor.',
        'Latest Real Property Tax Receipt (Tax Clearance)':
            'From City/Municipal Treasurer.',
        'Unsigned Deed of Donation (at least 5 copies)':
            'Must contain formal acceptance clause.',
      },
      copiesRecommended: 'At least 5 original sets.',
      whoMustAppear: 'Both the Donor and the Donee (to accept) must appear personally.',
    ),
    NotaryDocumentItem(
      title: 'Contract Signing & Lease Agreement',
      category: 'Contracts & Agreements',
      sampleAssetPath: 'assets/notary/deed_of_sale.jpg',
      description:
          'Notarization of tenancy leases, employment contracts, or service agreements so all signatures are legally acknowledged.',
      example:
          'You are leasing a commercial space, apartment, or signing a formal construction agreement with another party.',
      requiredDocuments: [
        'Both Contracting Parties Personal Appearance',
        'Valid Government IDs with photo and signature',
        'Proof of authority (if signing on behalf of a company or owner)',
        'Unsigned Contract / Lease Agreement (at least 3 copies)',
      ],
      documentHints: {
        'Both Contracting Parties Personal Appearance':
            'Lessor and lessee, or both contracting parties.',
        'Valid Government IDs with photo and signature':
            'Original valid IDs.',
        'Proof of authority (if signing on behalf of a company or owner)':
            'Board resolution, secretary certificate, or SPA.',
        'Unsigned Contract / Lease Agreement (at least 3 copies)':
            'Printed contract to be signed before the notary.',
      },
      whoMustAppear: 'All parties named in the agreement must appear personally.',
    ),
    NotaryDocumentItem(
      title: 'Sworn Statement / Declaration',
      category: 'Affidavits',
      sampleAssetPath: 'assets/notary/affidavit_of_loss.jpg',
      description:
          'A formal notarized declaration made under oath for an agency, school, board examination, or court requirement.',
      example:
          'A university, employer, or government board asks you to submit a notarized sworn declaration of income, residency, or non-employment.',
      requiredDocuments: [
        'Declarant / Affiant Personal Appearance',
        'Valid Government-issued Photo ID',
        'Unsigned Sworn Statement (at least 3 copies)',
        'Any supporting documents mentioned in the declaration',
      ],
      documentHints: {
        'Declarant / Affiant Personal Appearance':
            'The person taking the oath must appear.',
        'Valid Government-issued Photo ID':
            'Original government photo ID.',
        'Unsigned Sworn Statement (at least 3 copies)':
            'Printed statement.',
        'Any supporting documents mentioned in the declaration':
            'Payslips, certificates, or agency forms.',
      },
      whoMustAppear: 'The person taking the oath must appear personally.',
    ),
  ];

  static List<String> get categories {
    final set = <String>{};
    for (final doc in documents) {
      set.add(doc.category);
    }
    return set.toList();
  }

  /// Stream both custom Firestore notary services and built-in defaults
  static Stream<List<NotaryDocumentItem>> streamDocuments() {
    return FirebaseFirestore.instance
        .collection('notary_services')
        .snapshots()
        .map((snapshot) {
      final customList = snapshot.docs
          .map((doc) => NotaryDocumentItem.fromFirestore(doc))
          .toList();

      final customTitles = customList.map((c) => c.title.toLowerCase()).toSet();
      final defaultList = documents
          .where((d) => !customTitles.contains(d.title.toLowerCase()))
          .toList();

      return [...customList, ...defaultList];
    });
  }

  static Future<void> addDocument(NotaryDocumentItem item) async {
    await FirebaseFirestore.instance
        .collection('notary_services')
        .add(item.toMap());
  }

  static Future<void> updateDocument(String id, NotaryDocumentItem item) async {
    await FirebaseFirestore.instance
        .collection('notary_services')
        .doc(id)
        .set(item.toMap(), SetOptions(merge: true));
  }

  static Future<void> saveDocument(
    NotaryDocumentItem item, {
    String? id,
    String? originalTitle,
  }) async {
    final collection = FirebaseFirestore.instance.collection('notary_services');
    if (id != null && id.isNotEmpty) {
      await collection.doc(id).set(item.toMap(), SetOptions(merge: true));
      return;
    }
    final titleToMatch = originalTitle ?? item.title;
    final existingSnapshot = await collection
        .where('title', isEqualTo: titleToMatch)
        .limit(1)
        .get();

    if (existingSnapshot.docs.isNotEmpty) {
      await existingSnapshot.docs.first.reference.set(
        item.toMap(),
        SetOptions(merge: true),
      );
    } else {
      await collection.add(item.toMap());
    }
  }

  static Future<void> deleteDocument(String id) async {
    await FirebaseFirestore.instance
        .collection('notary_services')
        .doc(id)
        .delete();
  }

  static NotaryDocumentItem? findService(String title) {
    try {
      return documents.firstWhere(
        (d) => d.title.toLowerCase() == title.toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }

  static List<String> getRequiredDocuments(String serviceType) {
    final item = findService(serviceType);
    if (item != null) return item.requiredDocuments;
    return const [];
  }

  static String getDescription(String serviceType) {
    final item = findService(serviceType);
    return item?.description ?? 'Notarial service for official documents.';
  }

  static String getExample(String serviceType) {
    final item = findService(serviceType);
    return item?.example ??
        'Bring the unsigned original document and 2 valid government IDs to the office.';
  }

  static String getDocumentHint(String documentName) {
    for (final doc in documents) {
      if (doc.documentHints.containsKey(documentName)) {
        return doc.documentHints[documentName]!;
      }
    }
    return 'Bring the original copy of this document.';
  }

  static bool isValidServiceType(String serviceType) {
    return documents.any((d) => d.title.toLowerCase() == serviceType.toLowerCase());
  }

  /// Maps specific document requirement items to real example picture assets
  static String? getRequirementSampleImage(String requirementName) {
    final lower = requirementName.toLowerCase();
    if (lower.contains('valid id') ||
        lower.contains('ids of both') ||
        lower.contains('photo id') ||
        lower.contains('government id') ||
        lower.contains('parties personal appearance') ||
        lower.contains('sellers & buyers')) {
      return 'assets/notary/valid_ids_example.jpg';
    }
    if (lower.contains('birth certificate') ||
        lower.contains('psa') ||
        lower.contains('discrepancy')) {
      return 'assets/notary/psa_birth_cert_example.jpg';
    }
    if (lower.contains('joint affidavit')) {
      return 'assets/notary/joint_affidavit.jpg';
    }
    if (lower.contains('affidavit of loss')) {
      return 'assets/notary/affidavit_of_loss.jpg';
    }
    if (lower.contains('spa') || lower.contains('power of attorney')) {
      return 'assets/notary/special_power_of_attorney.jpg';
    }
    if (lower.contains('deed of absolute sale') ||
        lower.contains('deed of sale') ||
        lower.contains('contract') ||
        lower.contains('lease')) {
      return 'assets/notary/deed_of_sale.jpg';
    }
    return null;
  }

  /// Title for the sample requirement dialog/preview
  static String getRequirementSampleTitle(String requirementName) {
    final lower = requirementName.toLowerCase();
    if (lower.contains('valid id') ||
        lower.contains('ids of both') ||
        lower.contains('photo id') ||
        lower.contains('government id')) {
      return 'Sample Government Photo IDs (PhilID, Passport, Driver\'s License, UMID)';
    }
    if (lower.contains('birth certificate') ||
        lower.contains('psa') ||
        lower.contains('discrepancy')) {
      return 'Sample Philippine PSA Official Birth Certificate (SecPA)';
    }
    if (lower.contains('joint affidavit')) {
      return 'Sample Printed Joint Affidavit of Two Disinterested Persons';
    }
    if (lower.contains('affidavit of loss')) {
      return 'Sample Printed Affidavit of Loss Document';
    }
    if (lower.contains('spa') || lower.contains('power of attorney')) {
      return 'Sample Special Power of Attorney Document';
    }
    if (lower.contains('deed')) {
      return 'Sample Printed Deed of Absolute Sale';
    }
    return 'Sample Document Example';
  }

  /// Generates or returns a realistic legal sample template preview
  static String getSampleTemplate(NotaryDocumentItem doc) {
    if (doc.sampleTemplateText != null &&
        doc.sampleTemplateText!.trim().isNotEmpty) {
      return doc.sampleTemplateText!.trim();
    }

    final t = doc.title.toLowerCase();
    if (t.contains('loss')) {
      return '''
REPUBLIC OF THE PHILIPPINES )
CITY / MUNICIPALITY OF _________ ) S.S.

AFFIDAVIT OF LOSS

I, [AFFIANT FULL NAME], of legal age, Filipino, single/married, and a resident of [COMPLETE ADDRESS], after having been duly sworn in accordance with law, hereby depose and state:

1. That I am the legitimate holder/owner of the following document:
   • Type: [Driver's License / Official Receipt / Passport / ATM Card]
   • Identification No.: [ID OR ACCOUNT NUMBER]
   • Issued by: [ISSUING GOVERNMENT AGENCY OR BANK]

2. That on or about [DATE OF LOSS], the aforementioned item was lost under the following circumstances:
   [STATE CLEARLY WHERE AND HOW THE LOSS OCCURRED]

3. That despite diligent search and earnest efforts to retrieve and recover the said document, the same can no longer be found and is deemed lost beyond recovery;

4. That said document was not confiscated by any law enforcement agency, nor pledged as collateral for any obligation;

5. That I execute this Affidavit to attest to the truth of the foregoing facts and in support of my application for a REPLACEMENT thereof.

IN WITNESS WHEREOF, I have hereunto affixed my signature this _____ day of ________________, 20____ at ________________________, Philippines.


                                                _______________________________________
                                                [AFFIANT NAME]
                                                Affiant (Sign in presence of Notary)

SUBSCRIBED AND SWORN to before me this _____ day of ________________, 20____, affiant exhibiting Competent Evidence of Identity: [GOVERNMENT PHOTO ID NO. ____________].

Doc. No. _______;
Page No. _______;
Book No. _______;
Series of 20____.
''';
    }

    if (t.contains('disinterested') || t.contains('joint affidavit')) {
      return '''
REPUBLIC OF THE PHILIPPINES )
PROVINCE OF ________________ ) S.S.
CITY / MUNICIPALITY OF _____ )

JOINT AFFIDAVIT OF TWO DISINTERESTED PERSONS

WE, [WITNESS 1 NAME] and [WITNESS 2 NAME], both of legal age, Filipinos, and residing at [ADDRESS 1] and [ADDRESS 2] respectively, after being duly sworn to in accordance with law, depose and state:

1. That we personally know [NAME OF PERSON CONCERNED], having been neighbors and acquaintances for more than [NUMBER] years;

2. That we know for a fact that the said person was born on [DATE OF BIRTH] at [PLACE OF BIRTH] to spouses [FATHER'S NAME] and [MOTHER'S NAME];

3. That in their official records, particularly [STATE DISCREPANCY, e.g. spelling of first name or middle name], there exists a clerical error;

4. That the names [NAME A] and [NAME B] refer to one and the same person;

5. That we are not related by blood or marriage to the said subject person, nor do we have any financial interest in the matter;

6. That we execute this joint affidavit to attest to the truth of the foregoing facts for the PSA and all legal intents.

IN WITNESS WHEREOF, we have hereunto affixed our signatures this _____ day of ____________, 20____.


_________________________________               _________________________________
[WITNESS 1 NAME]                                [WITNESS 2 NAME]
Affiant                                         Affiant

SUBSCRIBED AND SWORN to before me this _____ day of ____________, 20____.
''';
    }

    if (t.contains('special power of attorney') || t.contains('spa') || t.contains('authorization')) {
      return '''
SPECIAL POWER OF ATTORNEY

KNOW ALL MEN BY THESE PRESENTS:

I, [PRINCIPAL NAME], of legal age, Filipino, residing at [PRINCIPAL ADDRESS], do hereby APPOINT, NAME, and CONSTITUTE:

[ATTORNEY-IN-FACT NAME], of legal age, Filipino, residing at [AGENT ADDRESS],

to be my true and lawful Attorney-in-Fact, for me and in my name, place, and stead, to perform the following acts and deeds:

1. To represent and act on my behalf before [GOVERNMENT AGENCY / BANK / OFFICE];
2. To claim, receive, sign, and endorse all relevant certificates, checks, and correspondence regarding [SPECIFIC PURPOSE];
3. To execute, deliver, and sign any and all papers or affidavits necessary to accomplish the above purpose.

HEREBY GIVING AND GRANTING unto my said Attorney-in-Fact full power and authority to do and perform all and every act requisite and necessary to be done in the premises.

IN WITNESS WHEREOF, I have hereunto set my hand this _____ day of ____________, 20____ at ________________, Philippines.


_________________________________               _________________________________
[PRINCIPAL NAME]                                [ATTORNEY-IN-FACT NAME]
Principal (Sign before Notary)                  Accepted by Attorney-in-Fact

ACKNOWLEDGMENT
REPUBLIC OF THE PHILIPPINES) S.S.

BEFORE ME, a Notary Public for and in the City of ____________, this _____ day of ____________, 20____, personally appeared the parties with their respective valid IDs.

Doc. No. _______; Page No. _______; Book No. _______; Series of 20____.
''';
    }

    if (t.contains('sale') || t.contains('deed')) {
      return '''
DEED OF ABSOLUTE SALE

KNOW ALL MEN BY THESE PRESENTS:

This DEED OF ABSOLUTE SALE is made and executed by:

[VENDOR NAME], of legal age, Filipino, single/married, residing at [VENDOR ADDRESS], hereinafter referred to as the "VENDOR";

- AND -

[VENDEE NAME], of legal age, Filipino, single/married, residing at [VENDEE ADDRESS], hereinafter referred to as the "VENDEE".

WITNESSETH:

That for and in consideration of the sum of [AMOUNT IN WORDS] (Php ____________.00) Philippine Currency, the VENDOR hereby SELLS, TRANSFERS, and CONVEYS unto the VENDEE, heirs, and assigns, the property described as follows:

[DETAILED PROPERTY DESCRIPTION / MOTOR VEHICLE / LAND TITLE PARTICULARS]

The VENDOR hereby warrants valid title and ownership free from any lien, claim, or encumbrance whatsoever.

IN WITNESS WHEREOF, the parties have signed this _____ day of ____________, 20____.


_________________________________               _________________________________
VENDOR (Sign before Notary)                     VENDEE (Sign before Notary)

SIGNED IN THE PRESENCE OF:
_________________________                       _________________________
Witness 1                                       Witness 2
''';
    }

    return '''
REPUBLIC OF THE PHILIPPINES )
CITY OF ____________________ ) S.S.

${doc.title.toUpperCase()}

I / WE, [AFFIANT / SIGNATORY NAME(S)], of legal age, Filipino, residing at [ADDRESS], after having been duly sworn in accordance with law, hereby depose and state:

1. That [STATE THE PRIMARY FACTUAL BACKGROUND AND PURPOSE OF THIS INSTRUMENT];
2. That [SPECIFY DETAILS, TERMS, CONDITIONS, OR DECLARATION];
3. That this document is executed freely and voluntarily for all legal intents and purposes.

IN WITNESS WHEREOF, I have hereunto set my hand this _____ day of ____________, 20____ at ________________, Philippines.


                                                _______________________________________
                                                Affiant / Signatory
                                                (Sign in the presence of Notary)

SUBSCRIBED AND SWORN to before me this _____ day of ____________, 20____, affiant exhibiting their Competent Evidence of Identity.

Doc. No. _______;
Page No. _______;
Book No. _______;
Series of 20____.
''';
  }
}
