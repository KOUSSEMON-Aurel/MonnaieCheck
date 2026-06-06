/// Modelization of the Legal Rules for FCFA according to Beninese Law (May 2026)
/// and BCEAO Directives.

enum Verdict {
  mandatoryAcceptance,
  legitimateRefusal,
  exchangeAtBCEAO
}

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

class RuleEngine {
  static const String legalRefusalPenalty = 
      "⚖️ Tout refus injustifié d'une monnaie ayant cours légal expose le contrevenant à une amende de 100 000 à 500 000 francs CFA (Loi du 22 mai 2026).";

  /// Logic for Banknotes
  static ValidationResult validateBanknote({
    required double surfacePercentage,
    required bool hasInscriptions,
    required bool isTornAndCleanlyRepaired,
    required bool isBurnedOrSeverelyWashed,
    required bool hasVisibleSerialNumber,
  }) {
    if (surfacePercentage < 50.0) {
      return ValidationResult(
        verdict: Verdict.legitimateRefusal,
        reason: "Surface restante < 50%.",
        legalNotice: "Le billet est trop amputé pour conserver son cours légal.",
      );
    }

    if (isBurnedOrSeverelyWashed && !hasVisibleSerialNumber) {
      return ValidationResult(
        verdict: Verdict.legitimateRefusal,
        reason: "Billet gravement altéré (brûlé/lavé) et sans numéro de série.",
        legalNotice: "L'authenticité ne peut être garantie.",
      );
    }

    if (surfacePercentage >= 50.0 && surfacePercentage < 100.0) {
       return ValidationResult(
        verdict: Verdict.exchangeAtBCEAO,
        reason: "Billet authentique mais endommagé.",
        legalNotice: "Échange gratuit possible aux guichets de la BCEAO.",
      );
    }

    // Default Case: Stained, written, or repaired
    return ValidationResult(
      verdict: Verdict.mandatoryAcceptance,
      reason: "Billet froissé, taché ou réparé proprement.",
      legalNotice: "L'acceptation est OBLIGATOIRE sous peine d'amende.\n$legalRefusalPenalty",
    );
  }

  /// Logic for Coins
  static ValidationResult validateCoin({
    required bool isWornNaturally,
    required bool isDrilledOrFormedByAlteration,
    required bool isWeldedToAnother,
  }) {
    if (isDrilledOrFormedByAlteration || isWeldedToAnother) {
      return ValidationResult(
        verdict: Verdict.legitimateRefusal,
        reason: "Pièce altérée volontairement (trouée, soudée, rognée).",
        legalNotice: "L'altération volontaire annule le cours légal de la pièce.",
      );
    }

    if (isWornNaturally) {
      return ValidationResult(
        verdict: Verdict.mandatoryAcceptance,
        reason: "Pièce lisse ou usée naturellement.",
        legalNotice: "L'usure naturelle ne justifie pas un refus.\n$legalRefusalPenalty",
      );
    }

    return ValidationResult(
      verdict: Verdict.mandatoryAcceptance,
      reason: "Pièce en bon état.",
      legalNotice: legalRefusalPenalty,
    );
  }
}
