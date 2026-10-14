package com.example.catalog.rates;

import static com.github.tomakehurst.wiremock.client.WireMock.getRequestedFor;
import static com.github.tomakehurst.wiremock.client.WireMock.urlPathEqualTo;
import static com.github.tomakehurst.wiremock.core.WireMockConfiguration.wireMockConfig;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.github.tomakehurst.wiremock.junit5.WireMockExtension;
import java.math.BigDecimal;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.RegisterExtension;
import org.springframework.web.client.RestClient;

/**
 * Each WireMock server loads its stubs from JSON files under {@code src/test/resources/wiremock}.
 */
class ExchangeRateClientTest {

  @RegisterExtension
  static WireMockExtension ok =
      WireMockExtension.newInstance()
          .options(wireMockConfig().dynamicPort().usingFilesUnderClasspath("wiremock/ok"))
          .build();

  @RegisterExtension
  static WireMockExtension missingCurrency =
      WireMockExtension.newInstance()
          .options(
              wireMockConfig().dynamicPort().usingFilesUnderClasspath("wiremock/missing-currency"))
          .build();

  @RegisterExtension
  static WireMockExtension serverError =
      WireMockExtension.newInstance()
          .options(wireMockConfig().dynamicPort().usingFilesUnderClasspath("wiremock/server-error"))
          .build();

  @RegisterExtension
  static WireMockExtension slow =
      WireMockExtension.newInstance()
          .options(wireMockConfig().dynamicPort().usingFilesUnderClasspath("wiremock/slow"))
          .build();

  private static ExchangeRateClient clientFor(WireMockExtension server) {
    return new ExchangeRateClient(RestClient.builder(), server.baseUrl());
  }

  @Test
  void rateFor_returnsRateFromJsonStub() {
    BigDecimal rate = clientFor(ok).rateFor("EUR");

    assertThat(rate).isEqualByComparingTo("0.92");
    ok.verify(1, getRequestedFor(urlPathEqualTo("/latest")));
  }

  @Test
  void rateFor_unknownCurrency_throws() {
    assertThatThrownBy(() -> clientFor(missingCurrency).rateFor("GBP"))
        .isInstanceOf(ExchangeRateUnavailableException.class)
        .hasMessageContaining("GBP");
  }

  @Test
  void rateFor_serverError_wrapsException() {
    assertThatThrownBy(() -> clientFor(serverError).rateFor("EUR"))
        .isInstanceOf(ExchangeRateUnavailableException.class)
        .hasMessageContaining("failed");
  }

  @Test
  void rateFor_slowUpstream_timesOut() {
    assertThatThrownBy(() -> clientFor(slow).rateFor("EUR"))
        .isInstanceOf(ExchangeRateUnavailableException.class);
  }
}
