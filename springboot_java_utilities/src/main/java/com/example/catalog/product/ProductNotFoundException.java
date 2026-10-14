package com.example.catalog.product;

/** Thrown when a product id does not exist. */
public class ProductNotFoundException extends RuntimeException {

  private static final long serialVersionUID = 1L;

  public ProductNotFoundException(long id) {
    super("Product " + id + " not found");
  }
}
