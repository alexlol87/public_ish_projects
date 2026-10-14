package com.example.catalog.product;

import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.example.catalog.rates.ExchangeRateUnavailableException;
import java.math.BigDecimal;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(ProductController.class)
class ProductControllerTest {

  @Autowired MockMvc mvc;
  @MockitoBean ProductService service;

  @Test
  void get_returnsProduct() throws Exception {
    when(service.get(1L))
        .thenReturn(new ProductResponse(1L, "Pen", "office", new BigDecimal("2.50")));

    mvc.perform(get("/api/products/1"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.name").value("Pen"));
  }

  @Test
  void get_missing_returns404() throws Exception {
    when(service.get(9L)).thenThrow(new ProductNotFoundException(9L));

    mvc.perform(get("/api/products/9")).andExpect(status().isNotFound());
  }

  @Test
  void create_valid_returns201WithLocation() throws Exception {
    when(service.create(new ProductRequest("Pen", "office", new BigDecimal("2.50"))))
        .thenReturn(new ProductResponse(5L, "Pen", "office", new BigDecimal("2.50")));

    mvc.perform(
            post("/api/products")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\":\"Pen\",\"category\":\"office\",\"priceUsd\":2.50}"))
        .andExpect(status().isCreated())
        .andExpect(header().string("Location", "/api/products/5"));
  }

  @Test
  void create_blankName_returns400() throws Exception {
    mvc.perform(
            post("/api/products")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"name\":\" \",\"category\":\"office\",\"priceUsd\":2.50}"))
        .andExpect(status().isBadRequest());
  }

  @Test
  void price_upstreamDown_returns502() throws Exception {
    when(service.quote(1L, "EUR")).thenThrow(new ExchangeRateUnavailableException("down"));

    mvc.perform(get("/api/products/1/price").param("currency", "EUR"))
        .andExpect(status().isBadGateway());
  }
}
