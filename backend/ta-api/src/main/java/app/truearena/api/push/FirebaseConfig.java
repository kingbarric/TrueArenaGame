package app.truearena.api.push;

import com.google.auth.oauth2.GoogleCredentials;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.messaging.FirebaseMessaging;
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
        return FirebaseMessaging.getInstance(app);
    }
}
