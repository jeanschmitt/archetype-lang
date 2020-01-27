// Solidity output generated by archetype 0.1.13

pragma solidity >=0.5.0 <0.7.0;

contract erc_20_gen {
  struct asset_balances {
    address addr;
    int value;
    bool isValue;
  }
  mapping(address => asset_balances) public balances;
  string symbol = "$TOKENSYMBOL";

  /* API functions */
  function get_balances(address k) private view returns(asset_balances storage) {
    return balances[k];
  }

  function set_balances(address k, asset_balances storage asset) private {
    balances[k] = asset;
  }

  function add_balances(asset_balances memory asset) private {
    address key = asset.addr;
    if (balances[key].isValue) {
      revert("key already exists");
    }
    balances[key] = asset;
  }

  function contains_balances(address key) private pure returns(bool) {
    return key == key;
  }


  function attributeTokens(address to_, int amount) public {
    if (!(amount >= 0)) {
      revert ("require r1 failed");
    }
    if (contains_balances (to_)) {
      address k_ = to_;
      asset_balances storage balances_ = get_balances (k_);
      balances_.value = balances_.value + amount;
    } else {
      asset_balances memory b = asset_balances({addr: to_, value: amount, isValue : true});
      add_balances (b);
    }
  }

  function decreaseMaxTokens(int amount) public {
    if (!(amount >= 0)) {
      revert ("require r2 failed");
    }
    if (get_balances (msg.sender).value < amount) {
      revert ("require r3 failed");
    }
    address k_ = msg.sender;
    asset_balances storage balances_ = get_balances (k_);
    balances_.value -= amount;
  }

  function transfer_(address to_, int amount) public {
    if (!(amount >= 0)) {
      revert ("require r4 failed");
    }
    if (get_balances (msg.sender).value < amount) {
      revert ("require r5 failed");
    }
    address k_ = msg.sender;
    asset_balances storage balances_ = get_balances (k_);
    balances_.value -= amount;
    if (contains_balances (to_)) {
      address k1_ = to_;
      asset_balances memory balances3_ = get_balances (k1_);
      balances3_.value += amount;
    } else {
      asset_balances memory b = asset_balances({addr: to_, value: amount, isValue : true});
      add_balances (b);
    }
  }
}
