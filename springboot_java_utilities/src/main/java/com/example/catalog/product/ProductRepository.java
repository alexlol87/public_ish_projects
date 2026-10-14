package com.example.catalog.product;

import java.math.BigDecimal;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/** Spring Data repository; the implementation is generated at startup. */
public interface ProductRepository extends JpaRepository<Product, Long> {

  List<Product> findByCategoryIgnoreCaseOrderByNameAsc(String category);

  /** Bound parameters, never string concatenation (see the SQL injection demo). */
  @Query("select p from Product p where p.priceUsd between :min and :max order by p.priceUsd")
  List<Product> findInPriceRange(@Param("min") BigDecimal min, @Param("max") BigDecimal max);
}
