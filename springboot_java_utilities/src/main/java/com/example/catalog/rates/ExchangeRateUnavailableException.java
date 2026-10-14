package com.example.catalog.rates;

/** The external rates API failed or did not know the currency. */
public class ExchangeRateUnavailableException extends RuntimeException {

  private static final long serialVersionUID = 1L;

  public ExchangeRateUnavailableException(String message) {
    super(message);
  }

  public ExchangeRateUnavailableException(String message, Throwable cause) {
    super(message, cause);
  }
}
