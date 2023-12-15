use actix_web::{
	post,
	web::{Data, Json},
	HttpResponse, Responder,
};
use serde::Deserialize;
use std::sync::Arc;

use crate::core::Core;

#[derive(Deserialize, Debug)]
struct Request {
	client_id: u64,
}

#[post("/unsubscribe")]
async fn main(request: Json<Request>, core: Data<Arc<Core>>) -> impl Responder {
	let unsubscribed = core.queue().unsubscribe(&request.client_id);

	if unsubscribed {
		HttpResponse::Ok().body("Unsubscribed successfully")
	} else {
		HttpResponse::BadRequest().body("Not subscribed")
	}
}
