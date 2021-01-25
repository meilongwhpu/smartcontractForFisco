pragma solidity ^0.4.25;
/// @dev Models a uint -> uint mapping where it is possible to iterate over all keys.
library IterableMapping {

  struct IndexValue {
      uint keyIndex;
      uint value;
  }

  struct KeyFlag {
      uint key;
      bool deleted;
 }
struct itmap{
    mapping(uint => IndexValue) data;
    KeyFlag[] keys;
    uint size;
  }

  function insert(itmap storage self, uint key, uint value) internal returns (bool replaced){
    uint keyIndex = self.data[key].keyIndex;
    self.data[key].value = value;
  if (keyIndex > 0){
       return true;
     } else{
       keyIndex = self.keys.length++;
       self.data[key].keyIndex = keyIndex + 1;
       self.keys[keyIndex].key = key;
       self.size++;
       return false;
     }
  }
  function remove(itmap storage self, uint key) internal returns (bool success){
    uint keyIndex = self.data[key].keyIndex;
    if (keyIndex == 0){
        return false;
    }
        delete self.data[key];
    self.keys[keyIndex - 1].deleted = true;
    self.size --;
  }
  function contains(itmap storage self, uint key) internal returns (bool){
    return self.data[key].keyIndex > 0;
  }
  function iterate_start(itmap storage self) internal returns (uint r_keyIndex){
    uint keyIndex=0;
     while (keyIndex < self.keys.length && self.keys[keyIndex].deleted){
       keyIndex++;
     }
    return keyIndex;
  }
  function iterate_valid(itmap storage self, uint keyIndex) internal returns (bool){
    return keyIndex < self.keys.length;
  }
  function iterate_next(itmap storage self, uint keyIndex) internal returns (uint r_keyIndex)  {
    keyIndex++;
    while (keyIndex < self.keys.length && self.keys[keyIndex].deleted){
      keyIndex++;
    }
    return keyIndex;
  }
  function iterate_get(itmap storage self, uint keyIndex) internal returns (uint key, uint value){
    key = self.keys[keyIndex].key;
    value = self.data[key].value;
  }
}
