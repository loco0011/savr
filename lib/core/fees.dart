import 'models.dart';

/// Typical fee rules per quick-commerce app, for a single-item order.
///
/// Search pages don't return fees, so live offers get an *estimate* from
/// these rules and the UI marks it with "≈". Apps change fees often and vary
/// them by city, time and membership; update this table when they do.
class FeeRule {
  const FeeRule({required this.freeAbove, required this.delivery, required this.handling, this.smallCartBelow, this.smallCart = 0});

  /// Delivery is free when the cart is at least this much.
  final double freeAbove;
  final double delivery;

  /// Charged on every order.
  final double handling;

  /// Extra charge for very small carts.
  final double? smallCartBelow;
  final double smallCart;

  double feeFor(double subtotal) =>
      (subtotal < freeAbove ? delivery : 0) +
      handling +
      (smallCartBelow != null && subtotal < smallCartBelow! ? smallCart : 0);
}

const kFeeRules = <String, FeeRule>{
  'blinkit': FeeRule(freeAbove: 199, delivery: 30, handling: 9, smallCartBelow: 99, smallCart: 20),
  'zepto': FeeRule(freeAbove: 199, delivery: 30, handling: 13, smallCartBelow: 99, smallCart: 25),
  'instamart': FeeRule(freeAbove: 199, delivery: 30, handling: 6, smallCartBelow: 99, smallCart: 15),
  'bbnow': FeeRule(freeAbove: 199, delivery: 30, handling: 5),
  'fkminutes': FeeRule(freeAbove: 199, delivery: 25, handling: 5),
  'amazonnow': FeeRule(freeAbove: 199, delivery: 25, handling: 5),
};

/// Adds an estimated fee to offers that don't carry a real one.
List<Offer> withEstimatedFees(List<Offer> offers) => [
  for (final o in offers)
    if (o.deliveryFee != null || kFeeRules[o.platformId] == null)
      o
    else
      o.copyWith(deliveryFee: kFeeRules[o.platformId]!.feeFor(o.price), feeIsEstimate: true),
];
