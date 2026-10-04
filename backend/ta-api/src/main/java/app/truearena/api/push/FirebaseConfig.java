package app.truearena.api.push;

import com.google.auth.oauth2.GoogleCredentials;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.messaging.FirebaseMessaging;
import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnExpression;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.util.Base64;

/**
 * Wires the Firebase Admin SDK from a base64'd service-account JSON (see
 * {@code truearena.push.firebase-credentials-base64} / {@code FIREBASE_CREDENTIALS_BASE64}
 * — base64 rather than a flat env var like {@code BREVO_API_KEY} because the
 * credential itself is multi-line JSON). When that's blank, no
 * {@link FirebaseMessaging} bean exists at all, and {@link PushNotificationService}
 * (which injects it as {@code @Autowired(required = false)}) falls back to its
 * local-profile stub — same "unconfigured means disabled, not broken" shape
 * as {@code EmailSender}.
 */
@Configuration
public class FirebaseConfig {

    private static final Logger log = LoggerFactory.getLogger(FirebaseConfig.class);

    // Unconditional — runs regardless of whether the bean below is created,
    // so a misconfigured credential shows up as a clear log line instead of
    // a silent "push just doesn't work". Logs shape only, never the value.
    @Value("${truearena.push.firebase-credentials-base64:}")
    private String diagnosticCredentialsBase64;

    @PostConstruct
    void logCredentialShape() {
        log.info("truearena.push.firebase-credentials-base64 resolved: blank={}, length={}",
                diagnosticCredentialsBase64.isBlank(), diagnosticCredentialsBase64.length());
    }

    @Bean
    @ConditionalOnExpression("!'${truearena.push.firebase-credentials-base64:}'.isBlank()")
    public FirebaseMessaging firebaseMessaging(
            @Value("${truearena.push.firebase-credentials-base64}") String credentialsBase64) throws IOException {
        byte[] json = Base64.getDecoder().decode(credentialsBase64);
        FirebaseOptions options = FirebaseOptions.builder()
                .setCredentials(GoogleCredentials.fromStream(new ByteArrayInputStream(json)))
                .build();
        FirebaseApp app = FirebaseApp.getApps().isEmpty()
                ? FirebaseApp.initializeApp(options)
                : FirebaseApp.getInstance();
        log.info("FirebaseMessaging bean created successfully");
        return FirebaseMessaging.getInstance(app);
    }
}
