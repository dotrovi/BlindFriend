// Malaysian IC (MyKad) number validator.
//
// IC format: YYMMDDPBXXXG (12 digits, no dashes)
//   YYMMDD – date of birth
//   PB     – state / place-of-birth code (2 digits)
//   XXX    – sequence number
//   G      – gender (odd = male, even = female)

class IcValidationResult {
  final bool isValid;
  final String? error;

  const IcValidationResult.valid() : isValid = true, error = null;
  const IcValidationResult.invalid(this.error) : isValid = false;
}

IcValidationResult validateMalaysianIc(String ic) {
  final cleaned = ic.trim();

  // Must be exactly 12 digits
  if (!RegExp(r'^\d{12}$').hasMatch(cleaned)) {
    return const IcValidationResult.invalid(
      'IC number must be exactly 12 digits (numbers only, no dashes)',
    );
  }

  // ── Date of birth (YYMMDD) ─────────────────────────────────────────────
  final mm = int.parse(cleaned.substring(2, 4));
  final dd = int.parse(cleaned.substring(4, 6));

  if (mm < 1 || mm > 12) {
    return const IcValidationResult.invalid(
      'IC number contains an invalid birth month',
    );
  }

  const daysInMonth = [0, 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];  // surely theres a better way to do this
  if (dd < 1 || dd > daysInMonth[mm]) {
    return const IcValidationResult.invalid(
      'IC number contains an invalid birth day',
    );
  }

  // ── State / place-of-birth code (PB) ──────────────────────────────────
  final pb = int.parse(cleaned.substring(6, 8));

  const validStateCodes = {
    // Malaysian states
    01, 02, 03, 04, 05, 06, 07, 08, 09, 10,
    11, 12, 13, 14, 15, 16,
    // Foreign countries
    21, 22, 23, 24, 25, 26, 27, 28, 29,
    30, 31, 32, 33, 34, 35, 36, 37, 38, 39,
    40, 41, 42, 43, 44, 45, 46, 47, 48, 49,
    50, 51, 52, 53, 54, 55, 56, 57, 58, 59,
    // Special / government-issued categories
    60, 61, 62, 63, 64, 65, 66,
    71, 72, 74,
    82, 83, 84, 85,
  };

  if (!validStateCodes.contains(pb)) {
    return const IcValidationResult.invalid(
      'IC number contains an unrecognised state or country code',
    );
  }

  return const IcValidationResult.valid();
}
