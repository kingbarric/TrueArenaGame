package app.truearena.api.ws;

import app.truearena.api.inbox.InboxWebSocketHandler;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.reactive.HandlerMapping;
import org.springframework.web.reactive.handler.SimpleUrlHandlerMapping;
import org.springframework.web.reactive.socket.WebSocketHandler;
import org.springframework.web.reactive.socket.server.support.WebSocketHandlerAdapter;

import java.util.Map;

/**
 * Wires {@link RoomWebSocketHandler} at {@code /ws/room/**} and
 * {@link InboxWebSocketHandler} at {@code /ws/inbox} — no @Controller/
 * @PathVariable for raw WS in WebFlux.
 */
@Configuration
public class WsConfig {

    @Bean
    public HandlerMapping wsHandlerMapping(RoomWebSocketHandler roomHandler, InboxWebSocketHandler inboxHandler) {
        SimpleUrlHandlerMapping mapping = new SimpleUrlHandlerMapping();
        mapping.setUrlMap(Map.<String, WebSocketHandler>of(
                "/ws/room/**", roomHandler,
                "/ws/inbox", inboxHandler));
        mapping.setOrder(-1);
        return mapping;
    }

    @Bean
    public WebSocketHandlerAdapter webSocketHandlerAdapter() {
        return new WebSocketHandlerAdapter();
    }
}
