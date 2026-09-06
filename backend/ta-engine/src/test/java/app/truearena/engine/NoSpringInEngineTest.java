package app.truearena.engine;

import com.tngtech.archunit.core.importer.ClassFileImporter;
import com.tngtech.archunit.lang.ArchRule;
import org.junit.jupiter.api.Test;

import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.noClasses;

/**
 * Architecture guard (Build Brief §8): the engine stays framework-free so it is
 * trivially testable and can never couple to the transport by accident.
 */
class NoSpringInEngineTest {

    @Test
    void engineHasNoSpringDependency() {
        ArchRule rule = noClasses()
                .that().resideInAPackage("app.truearena.engine..")
                .should().dependOnClassesThat().resideInAnyPackage(
                        "org.springframework..",
                        "jakarta.persistence..",
                        "io.r2dbc..");

        rule.check(new ClassFileImporter().importPackages("app.truearena.engine"));
    }
}
