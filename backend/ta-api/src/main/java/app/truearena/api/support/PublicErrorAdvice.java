package app.truearena.api.support;

import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.web.bind.support.WebExchangeBindException;

/** Internal details belong in logs, never in a public response. Codes retain app flow decisions. */
@RestControllerAdvice
public class PublicErrorAdvice {
    public static final String MESSAGE = "Error has occurred, try again later.";
    private static final Logger LOG = LoggerFactory.getLogger(PublicErrorAdvice.class);

    @ExceptionHandler(Exception.class)
    public ResponseEntity<Map<String, Object>> handle(Exception error) {
        int status = error instanceof ResponseStatusException r ? r.getStatusCode().value()
                : error instanceof WebExchangeBindException || error instanceof org.springframework.web.server.ServerWebInputException ? 400 : 500;
        if (status >= 500) LOG.error("Request failed", error);
        String reason = error instanceof ResponseStatusException r && r.getReason() != null ? r.getReason() : "";
        String code = reason.contains("already playing") ? "ALREADY_PLAYING"
                : reason.contains("already friends") ? "ALREADY_FRIENDS" : "REQUEST_FAILED";
        return ResponseEntity.status(status).body(Map.of("status", status, "code", code, "message", MESSAGE));
    }
}
