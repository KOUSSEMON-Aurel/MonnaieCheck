enum Verdict { mandatoryAcceptance, legitimateRefusal, exchangeAtBCEAO }

class ValidationResult {
  final Verdict verdict;
  final String reason;
  final String legalNotice;

  ValidationResult({
    required this.verdict,
    required this.reason,
    required this.legalNotice,
  });
}

class AnalysisMetrics {
  final bool isBanknote;
  final double surfacePercentage;
  final bool hasAnomalousInk;           // Result from LAB discriminator (Art. 14)
  final bool isSerialNumberReadable;
  final double textureSharpness;        // Laplacian score
  final double coinConvexity;           // Target >= 0.97
  final bool coinHasInternalHoles;      
  final bool coinIsWelded;
  final String? denomination;           // Identified from HSV/ORB

  AnalysisMetrics({
    required this.isBanknote,
    required this.surfacePercentage,
    this.hasAnomalousInk = false,
    this.isSerialNumberReadable = true,
    required this.textureSharpness,
    this.coinConvexity = 1.0,
    this.coinHasInternalHoles = false,
    this.coinIsWelded = false,
    this.denomination,
  });
}

class RuleEngine {
  static const String legalRefusalPenalty = "Conformément à la Loi du 22 mai 2026, le refus illégitime d'un billet ou d'une pièce ayant cours légal est passible d'une amende allant de 100 000 à 500 000 FCFA par infraction constatée.";

  static ValidationResult evaluate(AnalysisMetrics metrics) {
    const String disclaimer = "Outil d'aide citoyenne (Loi du 22 mai 2026). Seul le guichet de la BCEAO fait foi.";

    if (!metrics.isBanknote) {
      return _evaluateCoin(metrics, disclaimer);
    } else {
      return _evaluateBanknote(metrics, disclaimer);
    }
  }

  /// Compatibility method for older pipeline calls
  static ValidationResult validateBanknote(AnalysisMetrics metrics) {
    return _evaluateBanknote(metrics, "Outil d'aide citoyenne (Loi du 22 mai 2026).");
  }

  /// Compatibility method for older pipeline calls
  static ValidationResult validateCoin(AnalysisMetrics metrics) {
    return _evaluateCoin(metrics, "Outil d'aide citoyenne (Loi du 22 mai 2026).");
  }

  static ValidationResult _evaluateCoin(AnalysisMetrics metrics, String disclaimer) {
    if (metrics.coinIsWelded) {
      return ValidationResult(
        verdict: Verdict.legitimateRefusal,
        reason: "Pièce de monnaie altérée par soudure.",
        legalNotice: "Violation de l'Article 14 (Altération volontaire). REFUS LÉGITIME.",
      );
    }

    if (metrics.coinHasInternalHoles) {
      return ValidationResult(
        verdict: Verdict.legitimateRefusal,
        reason: "Pièce de monnaie volontairement trouée ou perforée.",
        legalNotice: "Article 14 : Le cours légal est annulé par la perforation. REFUS LÉGITIME.",
      );
    }

    if (metrics.coinConvexity < 0.97) {
      return ValidationResult(
        verdict: Verdict.legitimateRefusal,
        reason: "Pièce déformée, rognée ou sciée.",
        legalNotice: "Article 14 : Altération de la structure physique. REFUS LÉGITIME.",
      );
    }

    // Natural wear (Smooth coins)
    if (metrics.textureSharpness < 40.0) {
      return ValidationResult(
        verdict: Verdict.mandatoryAcceptance,
        reason: "Pièce lisse ou usée par la circulation (Usure naturelle).",
        legalNotice: "Loi du 22 mai 2026 : Le refus est passible d'une amende de 100 000 à 500 000 FCFA.",
      );
    }

    return ValidationResult(
      verdict: Verdict.mandatoryAcceptance,
      reason: "Pièce conforme et en bon état.",
      legalNotice: disclaimer,
    );
  }

  static ValidationResult _evaluateBanknote(AnalysisMetrics metrics, String disclaimer) {
    // 1. Mandatory Surface Rule (BCEAO < 50%)
    if (metrics.surfacePercentage < 50.0) {
      return ValidationResult(
        verdict: Verdict.legitimateRefusal,
        reason: "Surface inférieure à 50% (Billet amputé).",
        legalNotice: "Directives BCEAO : Refus légitime dans le commerce. Échange possible uniquement au guichet BCEAO.",
      );
    }

    // 2. Serial Number + High Degraded (>= 50% but < 75%)
    if (!metrics.isSerialNumberReadable && metrics.surfacePercentage < 75.0) {
      return ValidationResult(
        verdict: Verdict.exchangeAtBCEAO,
        reason: "Numéro de série illisible sur un billet fortement détérioré.",
        legalNotice: "Échange gratuit aux guichets de la BCEAO recommandé.",
      );
    }

    // 3. Stains / Ink (Art. 14 nuance)
    if (metrics.hasAnomalousInk) {
      return ValidationResult(
        verdict: Verdict.mandatoryAcceptance,
        reason: "Présence de tampons, écritures ou cachets sur le billet.",
        legalNotice: "Art. 14 : Le billet conserve son cours légal. REFUSER EST UNE INFRACTION (Amende 100k-500k).",
      );
    }

    // 4. Worn / Crumpled (Normal wear)
    if (metrics.textureSharpness < 45.0) {
      return ValidationResult(
        verdict: Verdict.mandatoryAcceptance,
        reason: "Billet froissé ou usé (Vieillissement normal).",
        legalNotice: "Loi du 22 mai 2026 : Interdiction de refuser les billets usés. Amende 100 000 à 500 000 FCFA.",
      );
    }

    return ValidationResult(
      verdict: Verdict.mandatoryAcceptance,
      reason: "Billet conforme.",
      legalNotice: "Dénomination identifiée: ${metrics.denomination ?? 'Inconnu'}. $disclaimer",
    );
  }
}
