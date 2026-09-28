use std::cell::RefCell;
use std::collections::HashMap;

use rowan::ast::AstNode;
use rowan::TextRange;
use yaml_parser::ast::{BlockMap, BlockMapEntry};

use crate::syntax::{extract_scalar_text, find_entry_by_key};

/// Maps with fewer entries than this are searched directly; scanning them is
/// cheaper than building and holding an index.
const MIN_INDEXED_ENTRIES: usize = 32;

/// Key lookups for large block maps, built the first time a key is looked up
/// in each map. Every edit reparses into a fresh `Document`, which discards
/// this along with the old tree.
#[derive(Debug, Default)]
pub(crate) struct KeyIndex {
  maps: RefCell<HashMap<TextRange, HashMap<String, BlockMapEntry>>>,
}

impl KeyIndex {
  pub(crate) fn find(&self, map: &BlockMap, key: &str) -> Option<BlockMapEntry> {
    let range = map.syntax().text_range();

    if let Some(entries) = self.maps.borrow().get(&range) {
      return entries.get(key).cloned();
    }

    if map.entries().count() < MIN_INDEXED_ENTRIES {
      return find_entry_by_key(map, key);
    }

    let mut entries = HashMap::new();

    for entry in map.entries() {
      if let Some(text) = entry.key().and_then(|key_node| extract_scalar_text(key_node.syntax())) {
        entries.entry(text).or_insert(entry);
      }
    }

    let found = entries.get(key).cloned();

    self.maps.borrow_mut().insert(range, entries);

    found
  }
}
