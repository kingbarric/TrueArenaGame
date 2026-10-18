package app.truearena.api.storage;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import reactor.core.publisher.Mono;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Duration;
import java.time.ZoneOffset;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.HexFormat;

/**
 * Files in the Cloudflare R2 bucket (S3 API, path-style, Signature V4). Off
 * unless the endpoint and keys are set — callers then keep their old storage.
 *
 * <p>Only PUT and GET of whole objects: that's all PlayHuud needs, and it
 * keeps a heavy SDK out of the backend.
 */
@Component
public class ObjectStorage {
    private static final DateTimeFormatter AMZ_DATE = DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss'Z'");
    private static final String EMPTY_SHA256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";

    private final URI endpoint;
    private final String bucket;
    private final String accessKey;
    private final String secretKey;
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();

    public ObjectStorage(@Value("${truearena.storage.r2.endpoint:}") String endpoint,
                         @Value("${truearena.storage.r2.bucket:playhuud-assets}") String bucket,
                         @Value("${truearena.storage.r2.access-key:}") String accessKey,
                         @Value("${truearena.storage.r2.secret-key:}") String secretKey) {
        this.endpoint = endpoint.isBlank() ? null : URI.create(endpoint.endsWith("/") ? endpoint : endpoint + "/");
        this.bucket = bucket;
        this.accessKey = accessKey;
        this.secretKey = secretKey;
    }

    public boolean enabled() {
        return endpoint != null && !accessKey.isBlank() && !secretKey.isBlank();
    }

    public Mono<Void> delete(String key) {
        return Mono.defer(() -> Mono.fromFuture(() -> http.sendAsync(
                signed("DELETE", key, EMPTY_SHA256).DELETE().build(), HttpResponse.BodyHandlers.discarding()))
                .flatMap(response -> response.statusCode()/100 == 2 || response.statusCode()==404
                        ? Mono.empty() : Mono.error(new IllegalStateException("Object erasure failed"))));
    }

    /** Stores {@code body} at {@code key}, cached by browsers and phones for a year (keys never change meaning). */
    public Mono<Void> put(String key, byte[] body, String contentType) {
        return Mono.defer(() -> {
            HttpRequest.Builder request = signed("PUT", key, sha256Hex(body))
                    .header("Content-Type", contentType)
                    .header("Cache-Control", "private, max-age=31536000, immutable")
                    .PUT(HttpRequest.BodyPublishers.ofByteArray(body));
            return Mono.fromFuture(() -> http.sendAsync(request.build(), HttpResponse.BodyHandlers.discarding()))
                    .flatMap(response -> response.statusCode() / 100 == 2 ? Mono.<Void>empty()
                            : Mono.error(new IllegalStateException("R2 PUT " + key + " failed: " + response.statusCode())));
        });
    }

    /** The object at {@code key}; empty when there is none. */
    public Mono<byte[]> get(String key) {
        return Mono.defer(() -> Mono.fromFuture(() -> http.sendAsync(signed("GET", key, EMPTY_SHA256).GET().build(),
                        HttpResponse.BodyHandlers.ofByteArray()))
                .flatMap(response -> switch (response.statusCode()) {
                    case 200 -> Mono.just(response.body());
                    case 404 -> Mono.<byte[]>empty();
                    default -> Mono.error(new IllegalStateException("R2 GET " + key + " failed: " + response.statusCode()));
                }));
    }

    private HttpRequest.Builder signed(String method, String key, String payloadHash) {
        if (!enabled()) throw new IllegalStateException("R2 storage is not configured");
        String path = "/" + encode(bucket) + "/" + encodePath(key);
        URI uri = endpoint.resolve(path.substring(1));
        String host = uri.getPort() == -1 ? uri.getHost() : uri.getHost() + ":" + uri.getPort();
        String amzDate = AMZ_DATE.format(ZonedDateTime.now(ZoneOffset.UTC));
        String day = amzDate.substring(0, 8);
        String scope = day + "/auto/s3/aws4_request";
        String signedHeaders = "host;x-amz-content-sha256;x-amz-date";
        String canonical = method + "\n" + path + "\n\n"
                + "host:" + host + "\n" + "x-amz-content-sha256:" + payloadHash + "\n" + "x-amz-date:" + amzDate + "\n\n"
                + signedHeaders + "\n" + payloadHash;
        String toSign = "AWS4-HMAC-SHA256\n" + amzDate + "\n" + scope + "\n" + sha256Hex(canonical.getBytes(StandardCharsets.UTF_8));
        byte[] signingKey = hmac(hmac(hmac(hmac(("AWS4" + secretKey).getBytes(StandardCharsets.UTF_8), day), "auto"), "s3"),
                "aws4_request");
        String signature = HexFormat.of().formatHex(hmac(signingKey, toSign));
        return HttpRequest.newBuilder(uri)
                .timeout(Duration.ofSeconds(20))
                .header("x-amz-content-sha256", payloadHash)
                .header("x-amz-date", amzDate)
                .header("Authorization", "AWS4-HMAC-SHA256 Credential=" + accessKey + "/" + scope
                        + ", SignedHeaders=" + signedHeaders + ", Signature=" + signature);
    }

    static String encodePath(String key) {
        StringBuilder out = new StringBuilder();
        for (String part : key.split("/", -1)) {
            if (!out.isEmpty()) out.append('/');
            out.append(encode(part));
        }
        return out.toString();
    }

    /** RFC 3986 unreserved characters stay; everything else is %XX, as Signature V4 expects. */
    static String encode(String s) {
        StringBuilder out = new StringBuilder();
        for (byte b : s.getBytes(StandardCharsets.UTF_8)) {
            char c = (char) (b & 0xff);
            if (c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '-' || c == '_' || c == '.' || c == '~') {
                out.append(c);
            } else {
                out.append('%').append(String.format("%02X", b & 0xff));
            }
        }
        return out.toString();
    }

    private static String sha256Hex(byte[] data) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(data));
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    private static byte[] hmac(byte[] key, String data) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(key, "HmacSHA256"));
            return mac.doFinal(data.getBytes(StandardCharsets.UTF_8));
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }
}
