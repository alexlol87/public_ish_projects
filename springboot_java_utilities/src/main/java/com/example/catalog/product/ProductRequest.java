package com.example.catalog.product;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.math.BigDecimal;

/** Body of {@code POST /api/products}. */
public record ProductRequest(
    @NotBlank String name,
    @NotBlank String category,
    @NotNull @DecimalMin("0.01") BigDecimal priceUsd) {}
