use anyhow::Result;
use crossbeam_channel::Receiver;
use rbx_dom_weak::types::Ref;
use serde::Serialize;
use std::{
	cmp,
	fs::File,
	io::BufWriter,
	path::{Path, PathBuf},
	sync::{Arc, Mutex, MutexGuard},
};

use self::{meta::Meta, processor::Processor, queue::Queue, tree::Tree};
use crate::{
	core::snapshot::Snapshot,
	lock,
	middleware::new_snapshot,
	project::Project,
	util::{self, PathExt},
	vfs::Vfs,
};

pub mod changes;
pub mod meta;
pub mod processor;
pub mod queue;
pub mod snapshot;
pub mod tree;

pub struct Core {
	project: Arc<Mutex<Project>>,
	processor: Arc<Processor>,
	queue: Arc<Mutex<Queue>>,
	tree: Arc<Mutex<Tree>>,
	_vfs: Arc<Vfs>,
}

impl Core {
	#[profiling::function]
	pub fn new(project: Project, watch: bool) -> Result<Self> {
		profiling::start_frame!();

		let vfs = Vfs::new(watch);

		let meta = Meta::from_project(&project);
		let snapshot = new_snapshot(&project.path, &meta, &vfs)?;

		let vfs = Arc::new(vfs);
		let tree = Arc::new(Mutex::new(Tree::new(snapshot.unwrap())));
		let queue = Arc::new(Mutex::new(Queue::new()));

		let project = Arc::new(Mutex::new(project));
		let processor = Processor::new(queue.clone(), tree.clone(), vfs.clone(), project.clone());

		Ok(Core {
			project,
			processor: Arc::new(processor),
			queue,
			tree,
			_vfs: vfs,
		})
	}

	pub fn name(&self) -> String {
		lock!(self.project).name.clone()
	}

	pub fn host(&self) -> Option<String> {
		lock!(self.project).host.clone()
	}

	pub fn port(&self) -> Option<u16> {
		lock!(self.project).port
	}

	pub fn game_id(&self) -> Option<u64> {
		lock!(self.project).game_id
	}

	pub fn place_ids(&self) -> Option<Vec<u64>> {
		lock!(self.project).place_ids.clone()
	}

	pub fn queue(&self) -> MutexGuard<'_, Queue> {
		lock!(self.queue)
	}

	pub fn tree_changed(&self) -> Receiver<bool> {
		self.processor.callback()
	}

	/// Create snapshot of the tree
	pub fn snapshot(&self) -> Snapshot {
		let tree = lock!(self.tree);

		fn walk(children: &[Ref], tree: &Tree) -> Vec<Snapshot> {
			let mut snapshot_children = vec![];

			for child in children {
				let child = tree.get_instance(*child).unwrap();

				let snapshot = Snapshot::new()
					.with_id(child.referent())
					.with_name(&child.name)
					.with_class(&child.class)
					.with_properties(child.properties.clone())
					.with_children(walk(child.children(), tree));

				snapshot_children.push(snapshot);
			}

			snapshot_children
		}

		let root = tree.root();

		Snapshot::new()
			.with_id(root.referent())
			.with_name(&root.name)
			.with_class(&root.class)
			.with_properties(root.properties.clone())
			.with_children(walk(tree.root().children(), &tree))
	}

	/// Build the tree into a file, either XML or binary
	pub fn build(&self, path: &Path, xml: bool) -> Result<()> {
		let writer = BufWriter::new(File::create(path)?);

		// We want to proritize event processing over building
		// so we can wait for the Mutex lock to release
		let tree = util::wait_for_mutex(&self.tree);

		let root_refs = if lock!(self.project).is_place() {
			tree.place_root_refs().to_vec()
		} else {
			vec![tree.root_ref()]
		};

		if xml {
			rbx_xml::to_writer_default(writer, tree.inner(), &root_refs)?;
		} else {
			rbx_binary::to_writer(writer, tree.inner(), &root_refs)?;
		}

		Ok(())
	}

	/// Write sourcemap of the tree
	pub fn sourcemap(&self, path: Option<PathBuf>, non_scripts: bool) -> Result<()> {
		let tree = util::wait_for_mutex(&self.tree);
		let dom = tree.inner();

		fn walk(tree: &Tree, id: Ref, non_scripts: bool) -> Option<SourcemapNode> {
			let instance = tree.get_instance(id).unwrap();

			let children: Vec<SourcemapNode> = instance
				.children()
				.iter()
				.filter_map(|&child_id| walk(tree, child_id, non_scripts))
				.collect();

			if children.is_empty() && (!non_scripts && !util::is_script(&instance.class)) {
				return None;
			}

			let mut file_paths: Vec<_> = tree
				.get_paths(id)
				.into_iter()
				.filter(|path| path.is_file())
				.cloned()
				.collect();

			file_paths.sort_by_key(|path| cmp::Reverse(path.len()));

			Some(SourcemapNode {
				name: instance.name.clone(),
				class_name: instance.class.clone(),
				file_paths,
				children,
			})
		}

		let sourcemap = walk(&tree, dom.root_ref(), non_scripts);

		if let Some(path) = path {
			let writer = BufWriter::new(File::create(path)?);
			serde_json::to_writer(writer, &sourcemap)?;
		} else {
			println!("{}", serde_json::to_string(&sourcemap)?);
		}

		Ok(())
	}
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct SourcemapNode {
	name: String,
	class_name: String,
	#[serde(skip_serializing_if = "Vec::is_empty")]
	file_paths: Vec<PathBuf>,
	#[serde(skip_serializing_if = "Vec::is_empty")]
	children: Vec<SourcemapNode>,
}
