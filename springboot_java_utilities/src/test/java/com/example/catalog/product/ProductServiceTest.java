package com.example.catalog.product;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.example.catalog.rates.ExchangeRateClient;
import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class ProductServiceTest {

  @Mock ProductRepository repository;
  @Mock ExchangeRateClient rates;
  @InjectMocks ProductService service;

  @Test
  void list_withoutCategory_returnsAll() {
    when(repository.findAll())
        .thenReturn(List.of(new Product("Pen", "office", new BigDecimal("2.50"))));

    assertThat(service.list(null)).extracting(ProductResponse::name).containsExactly("Pen");
  }

  @Test
  void list_withCategory_usesCategoryQuery() {
    when(repository.findByCategoryIgnoreCaseOrderByNameAsc("office")).thenReturn(List.of());

    assertThat(service.list("office")).isEmpty();
  }

  @Test
  void create_savesAndMaps() {
    when(repository.save(any(Product.class))).thenAnswer(call -> call.getArgument(0));

    ProductResponse created =
        service.create(new ProductRequest("Pen", "office", new BigDecimal("2.50")));

    assertThat(created.name()).isEqualTo("Pen");
    verify(repository).save(any(Product.class));
  }

  @Test
  void get_missing_throwsNotFound() {
    when(repository.findById(9L)).thenReturn(Optional.empty());

    assertThatThrownBy(() -> service.get(9L)).isInstanceOf(ProductNotFoundException.class);
  }

  @Test
  void delete_existing_deletesIt() {
    Product pen = new Product("Pen", "office", new BigDecimal("2.50"));
    when(repository.findById(1L)).thenReturn(Optional.of(pen));

    service.delete(1L);

    verify(repository).delete(pen);
  }

  @Test
  void quote_convertsAndRoundsHalfUp() {
    when(repository.findById(1L))
        .thenReturn(Optional.of(new Product("Pen", "office", new BigDecimal("2.50"))));
    when(rates.rateFor("EUR")).thenReturn(new BigDecimal("0.92"));

    PriceQuote quote = service.quote(1L, "eur");

    assertThat(quote.currency()).isEqualTo("EUR");
    assertThat(quote.price()).isEqualByComparingTo("2.30");
  }

  @Test
  void quote_invalidCurrency_throwsIllegalArgument() {
    assertThatThrownBy(() -> service.quote(1L, "euro"))
        .isInstanceOf(IllegalArgumentException.class);
  }
}
