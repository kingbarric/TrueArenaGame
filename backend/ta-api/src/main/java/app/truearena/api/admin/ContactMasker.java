package app.truearena.api.admin;

/** Shows just enough of a phone/email on the admin dashboard to recognize an account
 * without displaying it in full — this data is never meant to leave the admin page. */
final class ContactMasker {

    private ContactMasker() {
    }

    static String mask(String phone, String email) {
        if (phone != null && !phone.isBlank()) {
            return maskDigits(phone);
        }
        if (email != null && !email.isBlank()) {
            return maskEmail(email);
        }
        return "guest";
    }

    private static String maskDigits(String phone) {
        if (phone.length() <= 4) {
            return "***" + phone;
        }
        String prefix = phone.substring(0, Math.min(3, phone.length() - 2));
        String suffix = phone.substring(phone.length() - 2);
        return prefix + "***" + suffix;
    }

    private static String maskEmail(String email) {
        int at = email.indexOf('@');
        if (at <= 0) {
            return "***";
        }
        String local = email.substring(0, at);
        String domain = email.substring(at);
        String shown = local.length() <= 2 ? local : local.substring(0, 2);
        return shown + "***" + domain;
    }
}
