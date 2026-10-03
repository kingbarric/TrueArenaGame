package app.truearena.api.admin;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class ContactMaskerTest {

    @Test
    void phoneKeepsPrefixAndLastTwoDigits() {
        assertThat(ContactMasker.mask("+2348012345678", null)).isEqualTo("+23***78");
    }

    @Test
    void shortPhoneIsFullyMasked() {
        assertThat(ContactMasker.mask("123", null)).isEqualTo("***123");
    }

    @Test
    void emailKeepsFirstTwoCharsAndDomain() {
        assertThat(ContactMasker.mask(null, "someone@example.com")).isEqualTo("so***@example.com");
    }

    @Test
    void shortEmailLocalPartStaysWhole() {
        assertThat(ContactMasker.mask(null, "ab@example.com")).isEqualTo("ab***@example.com");
    }

    @Test
    void guestWithNeitherIsLabeledGuest() {
        assertThat(ContactMasker.mask(null, null)).isEqualTo("guest");
    }
}
