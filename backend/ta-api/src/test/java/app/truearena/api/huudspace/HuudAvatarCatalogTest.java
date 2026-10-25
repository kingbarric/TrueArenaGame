package app.truearena.api.huudspace;
import app.truearena.api.slay.SlayCatalog;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.web.server.ResponseStatusException;
import static org.assertj.core.api.Assertions.*;
class HuudAvatarCatalogTest {
    @Test void allFiveAvatarsHaveTenBodyCompatibleOutfitsAndUnknownChoicesAreRejected() throws Exception {
        var mapper=new ObjectMapper();
        var catalog=new HuudAvatarCatalog(mapper,new SlayCatalog(mapper,""));
        assertThat(catalog.options().avatars()).hasSize(5);
        assertThat(catalog.options().outfits()).hasSize(10);
        for(var avatar:catalog.options().avatars()) for(var outfit:catalog.options().outfits())
            catalog.validate(avatar.id(),outfit.id());
        assertThatThrownBy(()->catalog.validate("missing","everyday")).isInstanceOf(ResponseStatusException.class);
        assertThatThrownBy(()->catalog.validate("ella","missing")).isInstanceOf(ResponseStatusException.class);
    }
}
