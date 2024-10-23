use anyhow::Result;
use rbx_dom_weak::types::{Enum, Variant};
use std::{collections::HashMap, path::Path};

use super::Middleware;
use crate::{
	core::{meta::Context, snapshot::Snapshot},
	vfs::Vfs,
	Properties,
};

#[derive(Debug, Clone, PartialEq)]
pub enum ScriptType {
	Server,
	Client,
	Module,
}

impl From<Middleware> for ScriptType {
	fn from(middleware: Middleware) -> Self {
		match middleware {
			Middleware::ServerScript => ScriptType::Server,
			Middleware::ClientScript => ScriptType::Client,
			Middleware::ModuleScript => ScriptType::Module,
			_ => panic!("Cannot convert {:?} to ScriptType", middleware),
		}
	}
}

#[profiling::function]
pub fn read_luau(path: &Path, context: &Context, vfs: &Vfs, script_type: ScriptType) -> Result<Snapshot> {
	let (class_name, run_context) = match (context.use_legacy_scripts(), &script_type) {
		(false, ScriptType::Server) => ("Script", Some(Variant::Enum(Enum::from_u32(1)))),
		(false, ScriptType::Client) => ("Script", Some(Variant::Enum(Enum::from_u32(2)))),
		(true, ScriptType::Server) => ("Script", Some(Variant::Enum(Enum::from_u32(0)))),
		(true, ScriptType::Client) => ("LocalScript", None),
		(_, ScriptType::Module) => ("ModuleScript", None),
	};

	let mut snapshot = Snapshot::new().with_class(class_name);
	let mut properties = HashMap::new();

	let source = vfs.read_to_string(path)?;

	if script_type != ScriptType::Module {
		if let Some(run_context) = run_context {
			properties.insert(String::from("RunContext"), run_context);
		}
	}

	properties.insert(String::from("Source"), Variant::String(source));
	snapshot.set_properties(properties);

	Ok(snapshot)
}

#[profiling::function]
pub fn write_luau(mut properties: Properties, path: &Path, vfs: &Vfs) -> Result<Properties> {
	if let Some(Variant::String(value)) = properties.remove("Source") {
		vfs.write(path, value.as_bytes())?;
	}

	Ok(properties)
}
