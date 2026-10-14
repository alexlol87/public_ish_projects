package com.example.catalog.product;

import java.math.BigDecimal;

/** Product as returned by the API. */
public record ProductResponse(Long id, String name, String category, BigDecimal priceUsd) {

  static ProductResponse from(Product product) {
    return new ProductResponse(
        product.getId(), product.getName(), product.getCategory(), product.getPriceUsd());
  }
}
