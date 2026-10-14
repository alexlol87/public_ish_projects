package com.example.catalog;

import static com.github.tomakehurst.wiremock.core.WireMockConfiguration.wireMockConfig;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.github.tomakehurst.wiremock.junit5.WireMockExtension;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.RegisterExtension;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;

/** Whole stack: controller, service, JPA/H2 and the HTTP client against a WireMock server. */
@SpringBootTest
@AutoConfigureMockMvc
class CatalogIntegrationTest {

  @RegisterExtension
  static WireMockExtension rates =
      WireMockExtension.newInstance()
          .options(wireMockConfig().dynamicPort().usingFilesUnderClasspath("wiremock/ok"))
          .build();

  @DynamicPropertySource
  static void ratesUrl(DynamicPropertyRegistry registry) {
    registry.add("exchange.base-url", rates::baseUrl);
  }

  @Autowired MockMvc mvc;

  @Test
  void createThenQuote_endToEnd() throws Exception {
    mvc.perform(
            post("/api/products")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\":\"Desk\",\"category\":\"furniture\",\"priceUsd\":100.00}"))
        .andExpect(status().isCreated());

    mvc.perform(get("/api/products").param("category", "furniture"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$[0].name").value("Desk"));

    mvc.perform(get("/api/products/1/price").param("currency", "eur"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.price").value(92.0));
  }
}
