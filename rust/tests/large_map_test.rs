mod support;
use support::parse;

// Maps this large are looked up through a cached key index rather than a scan.
fn large_map_yaml(count: usize) -> String {
  (0..count).map(|i| format!("key{i}:\n  name: item{i}\n")).collect()
}

#[test]
fn test_large_map_finds_every_key() {
  let document = parse(&large_map_yaml(100));

  for i in [0, 1, 50, 99] {
    assert_eq!(document.get(&format!("key{i}.name")), Some(format!("item{i}")));
  }
}

#[test]
fn test_large_map_misses_absent_key() {
  let document = parse(&large_map_yaml(100));

  assert_eq!(document.get("key100.name"), None);
  assert!(!document.exists("key100"));
  assert_eq!(document.get("key0.name"), Some("item0".to_string()));
  assert_eq!(document.get("key100.name"), None);
}

#[test]
fn test_large_map_matches_quoted_keys() {
  let yaml = format!("{}\"quoted key\":\n  name: quoted\n'single': plain\n", large_map_yaml(40));
  let document = parse(&yaml);

  assert_eq!(document.get("quoted key.name"), Some("quoted".to_string()));
  assert_eq!(document.get("single"), Some("plain".to_string()));
}

#[test]
fn test_large_map_lookups_reflect_edits() {
  let mut document = parse(&large_map_yaml(100));

  assert_eq!(document.get("key50.name"), Some("item50".to_string()));
  assert_eq!(document.get("key99.name"), Some("item99".to_string()));

  document.set("key50.name", "changed").unwrap();
  document.delete("key99").unwrap();
  document.rename("key98", "renamed").unwrap();

  assert_eq!(document.get("key50.name"), Some("changed".to_string()));
  assert_eq!(document.get("key99.name"), None);
  assert_eq!(document.get("key98.name"), None);
  assert_eq!(document.get("renamed.name"), Some("item98".to_string()));
}

#[test]
fn test_large_map_lookups_reflect_same_length_edits() {
  let mut document = parse(&large_map_yaml(100));

  assert_eq!(document.get("key50.name"), Some("item50".to_string()));

  document.set("key50.name", "edited").unwrap();

  assert_eq!(document.get("key50.name"), Some("edited".to_string()));
}

#[test]
fn test_large_nested_map_lookup() {
  let yaml = format!("outer:\n{}", large_map_yaml(60).lines().map(|line| format!("  {line}\n")).collect::<String>());
  let document = parse(&yaml);

  assert_eq!(document.get("outer.key59.name"), Some("item59".to_string()));
  assert_eq!(document.get("outer.key0.name"), Some("item0".to_string()));
  assert_eq!(document.get_node_info("outer.key59").key_location.start_line, 120);
}
