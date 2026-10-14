package com.example.catalog.product;

import com.example.catalog.rates.ExchangeRateClient;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.List;
import java.util.Locale;
import java.util.regex.Pattern;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Business logic: CRUD plus currency conversion through the external rates API. */
@Service
public class ProductService {

  private static final Pattern CURRENCY_CODE = Pattern.compile("[A-Z]{3}");

  private final ProductRepository repository;
  private final ExchangeRateClient rates;

  public ProductService(ProductRepository repository, ExchangeRateClient rates) {
    this.repository = repository;
    this.rates = rates;
  }

  @Transactional(readOnly = true)
  public List<ProductResponse> list(String category) {
    List<Product> products =
        category == null
            ? repository.findAll()
            : repository.findByCategoryIgnoreCaseOrderByNameAsc(category);
    return products.stream().map(ProductResponse::from).toList();
  }

  @Transactional(readOnly = true)
  public ProductResponse get(long id) {
    return ProductResponse.from(find(id));
  }

  @Transactional
  public ProductResponse create(ProductRequest request) {
    Product saved =
        repository.save(new Product(request.name(), request.category(), request.priceUsd()));
    return ProductResponse.from(saved);
  }

  @Transactional
  public void delete(long id) {
    repository.delete(find(id));
  }

  @Transactional(readOnly = true)
  public PriceQuote quote(long id, String currency) {
    String code = currency.toUpperCase(Locale.ROOT);
    if (!CURRENCY_CODE.matcher(code).matches()) {
      throw new IllegalArgumentException("Currency must be a 3-letter code: " + currency);
    }
    Product product = find(id);
    BigDecimal rate = rates.rateFor(code);
    BigDecimal price = product.getPriceUsd().multiply(rate).setScale(2, RoundingMode.HALF_UP);
    return new PriceQuote(id, code, rate, price);
  }

  private Product find(long id) {
    return repository.findById(id).orElseThrow(() -> new ProductNotFoundException(id));
  }
}
