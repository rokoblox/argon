use anyhow::{bail, Result};
use log::error;
use rbx_dom_weak::types::Tags;
use serde::Deserialize;
use serde_json::Value;
use std::{collections::HashMap, path::Path};

use crate::{
	core::{meta::Meta, snapshot::Snapshot},
	ext::PathExt,
	resolution::UnresolvedValue,
	util,
	vfs::Vfs,
};

#[derive(Deserialize, Debug)]
struct ArgonData(HashMap<String, UnresolvedValue>);

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
struct RojoData {
	pub properties: Option<HashMap<String, UnresolvedValue>>,
	pub attributes: Option<UnresolvedValue>,
	// For consistency
	pub tags: Option<Vec<String>>,
}

#[profiling::function]
pub fn snapshot_data(path: &Path, _meta: &Meta, vfs: &Vfs) -> Result<Snapshot> {
	let data = vfs.read(path)?;
	let data: Value = serde_json::from_str(&data)?;

	let mut properties = HashMap::new();

	let class = {
		let parent = path.get_parent();

		// Get the class from the data file if one exists
		if let Some(class) = data.get("ClassName").or(data.get("className")) {
			let class = class.as_str();

			if class.is_none() {
				bail!("ClassName property is not a string");
			}

			class.unwrap().to_owned()
		// Get the class from the parent folder name,
		// only if it's a service and fallback to `Folder`
		} else {
			let name = parent.get_file_name();
			let is_service = util::is_service(name);

			if is_service {
				name.to_owned()
			} else {
				String::from("Folder")
			}
		}
	};

	if data.get("className").is_some()
		|| data.get("properties").is_some()
		|| data.get("attributes").is_some()
		|| data.get("ignoreUnknownInstances").is_some()
	// Read Rojo instance data
	{
		let data: RojoData = serde_json::from_value(data)?;

		// Resolve properties
		if let Some(data_properties) = data.properties {
			for (property, value) in data_properties {
				match value.resolve(&class, &property) {
					Ok(value) => {
						properties.insert(property, value);
					}
					Err(err) => {
						error!("Failed to parse property: {}", err);
					}
				}
			}
		}

		// Resolve attributes
		if let Some(attributes) = data.attributes {
			match attributes.resolve(&class, "Attributes") {
				Ok(value) => {
					properties.insert(String::from("Attributes"), value);
				}
				Err(err) => {
					error!("Failed to parse attributes: {}", err);
				}
			}
		}

		// Resolve tags
		if let Some(tags) = data.tags {
			properties.insert(String::from("Tags"), Tags::from(tags).into());
		}

	// Read Argon instance data
	} else {
		let data: ArgonData = serde_json::from_value(data)?;

		// Resolve everything
		for (property, value) in data.0 {
			if property == "ClassName" {
				continue;
			}

			match value.resolve(&class, &property) {
				Ok(value) => {
					properties.insert(property, value);
				}
				Err(err) => {
					error!("Failed to parse property: {}", err);
				}
			}
		}
	}

	Ok(Snapshot::new().with_class(&class).with_properties(properties))
}