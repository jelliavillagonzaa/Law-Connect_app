class NotaryServiceConfig {
  // Service descriptions
  static const Map<String, String> serviceDescriptions = {
    'Affidavit Notarization': 'Notarize your affidavit documents',
    'Special Power of Attorney (SPA)': 'Notarize your Special Power of Attorney',
    'General Power of Attorney': 'Notarize your General Power of Attorney',
    'Deed of Sale': 'Notarize your Deed of Sale documents',
    'Deed of Donation': 'Notarize your Deed of Donation',
    'Contract Signing': 'Notarize your contract documents',
    'Sworn Statement / Declaration': 'Notarize your sworn statement or declaration',
  };

  // Required documents for each service type
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

  // Get required documents for a service type
  static List<String> getRequiredDocuments(String serviceType) {
    return requiredDocuments[serviceType] ?? [];
  }

  // Get description for a service type
  static String getDescription(String serviceType) {
    return serviceDescriptions[serviceType] ?? 'Notary service';
  }

  // Check if service type is valid
  static bool isValidServiceType(String serviceType) {
    return requiredDocuments.containsKey(serviceType);
  }
}

