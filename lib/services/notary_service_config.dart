class NotaryServiceConfig {
  static const Map<String, String> serviceDescriptions = {
    'Affidavit Notarization':
        'A notarized sworn statement of facts that you personally know to be true.',
    'Special Power of Attorney (SPA)':
        'Lets a person you name do a specific act for you, such as claim documents or sell one property.',
    'General Power of Attorney':
        'Lets a person you name handle a broader set of legal or financial acts on your behalf.',
    'Deed of Sale':
        'The notarized document that records a sale of land, a house, or a vehicle.',
    'Deed of Donation':
        'The notarized document that records a gift of property to a relative or another person.',
    'Contract Signing':
        'Notarization of a contract so the parties’ signatures are acknowledged.',
    'Sworn Statement / Declaration':
        'A notarized declaration you make under oath for an agency, school, or court requirement.',
  };

  static const Map<String, String> serviceExamples = {
    'Affidavit Notarization':
        'You lost an ID and a bank, PSA, or DFA office asks for a sworn affidavit of loss.',
    'Special Power of Attorney (SPA)':
        'You are away from Oroquieta and need a relative to claim papers or sign one transaction for you.',
    'General Power of Attorney':
        'You want a spouse or child to manage several legal or financial matters while you cannot.',
    'Deed of Sale':
        'You are buying or selling land, a house, or a vehicle and both sides need a notarized deed.',
    'Deed of Donation':
        'You are giving property to a child or relative and need the donation notarized.',
    'Contract Signing':
        'You and the other party already have a contract and need the signatures notarized.',
    'Sworn Statement / Declaration':
        'A school, employer, or government office asks you to submit a notarized sworn statement.',
  };

  static const Map<String, List<String>> requiredDocuments = {
    'Affidavit Notarization': [
      'Valid ID (Government-issued)',
      'Affidavit Document',
    ],
    'Special Power of Attorney (SPA)': [
      'Valid ID (Government-issued)',
      'SPA Document',
      'Supporting Documents',
    ],
    'General Power of Attorney': [
      'Valid ID (Government-issued)',
      'General POA Document',
      'Supporting Documents',
    ],
    'Deed of Sale': [
      'Valid ID (Government-issued)',
      'Deed of Sale Document',
      'Property Documents',
      'Tax Documents',
    ],
    'Deed of Donation': [
      'Valid ID (Government-issued)',
      'Deed of Donation Document',
      'Property Documents',
      'Tax Documents',
    ],
    'Contract Signing': [
      'Valid ID (Government-issued)',
      'Contract Document',
      'Supporting Documents',
    ],
    'Sworn Statement / Declaration': [
      'Valid ID (Government-issued)',
      'Sworn Statement Document',
    ],
  };

  static const Map<String, String> documentHints = {
    'Valid ID (Government-issued)':
        'Bring the original PhilID, passport, or driver’s license.',
    'Affidavit Document':
        'Bring the unsigned affidavit to be notarized.',
    'SPA Document':
        'Bring the Special Power of Attorney to be notarized.',
    'General POA Document':
        'Bring the General Power of Attorney to be notarized.',
    'Supporting Documents':
        'Bring papers related to the authority you are giving.',
    'Deed of Sale Document':
        'Bring the deed of sale to be notarized.',
    'Property Documents':
        'Bring the title, tax declaration, or other property papers.',
    'Tax Documents':
        'Bring the latest tax receipt or related BIR/LGU papers.',
    'Contract Document':
        'Bring the contract both parties will sign.',
    'Sworn Statement Document':
        'Bring the unsigned sworn statement or declaration.',
  };

  static List<String> getRequiredDocuments(String serviceType) {
    return requiredDocuments[serviceType] ?? [];
  }

  static String getDescription(String serviceType) {
    return serviceDescriptions[serviceType] ?? 'Notary service';
  }

  static String getExample(String serviceType) {
    return serviceExamples[serviceType] ??
        'Use this when you need this document notarized by the law firm.';
  }

  static String getDocumentHint(String documentName) {
    return documentHints[documentName] ?? 'Bring the original of this document.';
  }

  static bool isValidServiceType(String serviceType) {
    return requiredDocuments.containsKey(serviceType);
  }
}
