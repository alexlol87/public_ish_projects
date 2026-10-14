package com.example.catalog.rates;

import java.math.BigDecimal;
import java.time.Duration;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

/** Calls the external exchange-rate API (mocked with WireMock in tests). */
@Component
public class ExchangeRateClient {

  private static final Duration TIMEOUT = Duration.ofSeconds(2);

  private final RestClient client;

  public ExchangeRateClient(
      RestClient.Builder builder, @Value("${exchange.base-url}") String baseUrl) {
    SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
    factory.setConnectTimeout(TIMEOUT);
    factory.setReadTimeout(TIMEOUT);
    this.client = builder.baseUrl(baseUrl).requestFactory(factory).build();
  }

  /** Returns how many units of {@code currency} one USD buys. */
  public BigDecimal rateFor(String currency) {
    RatesResponse body;
    try {
      body = client.get().uri("/latest?base=USD").retrieve().body(RatesResponse.class);
    } catch (RestClientException e) {
      throw new ExchangeRateUnavailableException("Exchange rate API call failed", e);
    }
    BigDecimal rate = body == null ? null : body.rate(currency);
    if (rate == null) {
      throw new ExchangeRateUnavailableException("No exchange rate for " + currency);
    }
    return rate;
  }

  /** JSON shape: {@code {"base":"USD","rates":{"EUR":0.92}}}. */
  record RatesResponse(String base, Map<String, BigDecimal> rates) {

    RatesResponse {
      rates = rates == null ? Map.of() : Map.copyOf(rates);
    }

    BigDecimal rate(String currency) {
      return rates.get(currency);
    }
  }
}
