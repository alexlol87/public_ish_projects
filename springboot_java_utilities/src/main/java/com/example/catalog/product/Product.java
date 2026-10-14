package com.example.catalog.product;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.math.BigDecimal;

/** A catalog item; the price is always stored in USD. */
@Entity
@Table(name = "products")
public class Product {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(nullable = false)
  private String name;

  @Column(nullable = false)
  private String category;

  @Column(nullable = false, precision = 12, scale = 2)
  private BigDecimal priceUsd;

  /** Required by JPA. */
  protected Product() {}

  public Product(String name, String category, BigDecimal priceUsd) {
    this.name = name;
    this.category = category;
    this.priceUsd = priceUsd;
  }

  public Long getId() {
    return id;
  }

  public String getName() {
    return name;
  }

  public String getCategory() {
    return category;
  }

  public BigDecimal getPriceUsd() {
    return priceUsd;
  }
}
