package com.example.catalog.product;

import java.math.BigDecimal;

/** A product price converted to another currency. */
public record PriceQuote(Long productId, String currency, BigDecimal rate, BigDecimal price) {}
