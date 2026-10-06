package app.truearena.api.ws;

import app.truearena.room.ChatMessage;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/** The orchestrator-side Traitors rules found in the October 2026 audit. */
class TraitorsTableRulesTest {

    @Test
    @DisplayName("Assigning an absent player's vote is a host action, like the other moderator actions")
    void hostAssignVoteIsHostOnly() {
        assertThat(GameOrchestrator.isHostOnlyAction("HOST_ASSIGN_VOTE")).isTrue();
        assertThat(GameOrchestrator.isHostOnlyAction("ADVANCE_PHASE")).isTrue();
        assertThat(GameOrchestrator.isHostOnlyAction("CAST_VOTE")).isFalse();
        assertThat(GameOrchestrator.isHostOnlyAction("NIGHT_TARGET")).isFalse();
    }

    @Test
    @DisplayName("Traitors can talk at night to agree a target; the table still only talks at the round table")
    void traitorsChannelOpensAtNight() {
        assertThat(GameOrchestrator.chatOpenInPhase(ChatMessage.TRAITORS, "Night")).isTrue();
        assertThat(GameOrchestrator.chatOpenInPhase(ChatMessage.TRAITORS, "RoundTable")).isTrue();
        assertThat(GameOrchestrator.chatOpenInPhase(ChatMessage.TABLE, "Night")).isFalse();
        assertThat(GameOrchestrator.chatOpenInPhase(ChatMessage.TABLE, "RoundTable")).isTrue();
        assertThat(GameOrchestrator.chatOpenInPhase(ChatMessage.TRAITORS, "Vote")).isFalse();
    }
}
