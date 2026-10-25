package app.truearena.api.slay;

import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestControllerAdvice(assignableTypes = SlayController.class)
public class SlayErrors {
    @ExceptionHandler(IllegalArgumentException.class)
    ResponseEntity<Map<String, String>> badRequest(IllegalArgumentException error) {
        return ResponseEntity.badRequest()
                .body(
                        Map.of(
                                "message",
                                error.getMessage() == null
                                        ? "Invalid styling request"
                                        : error.getMessage()));
    }
}
