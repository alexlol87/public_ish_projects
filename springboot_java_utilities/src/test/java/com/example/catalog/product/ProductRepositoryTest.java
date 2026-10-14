package com.example.catalog.product;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;

@DataJpaTest
class ProductRepositoryTest {

  @Autowired ProductRepository repository;

  @BeforeEach
  void seed() {
    repository.saveAll(
        List.of(
            new Product("Pen", "office", new BigDecimal("2.50")),
            new Product("Desk", "furniture", new BigDecimal("199.00")),
            new Product("Stapler", "Office", new BigDecimal("9.90"))));
  }

  @Test
  void findByCategory_ignoresCaseAndSortsByName() {
    assertThat(repository.findByCategoryIgnoreCaseOrderByNameAsc("OFFICE"))
        .extracting(Product::getName)
        .containsExactly("Pen", "Stapler");
  }

  @Test
  void findInPriceRange_isInclusiveAndSortedByPrice() {
    assertThat(repository.findInPriceRange(new BigDecimal("2.50"), new BigDecimal("10")))
        .extracting(Product::getName)
        .containsExactly("Pen", "Stapler");
  }
}
