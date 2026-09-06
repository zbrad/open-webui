import { OPENAI_API_BASE_URL, WEBUI_API_BASE_URL, WEBUI_BASE_URL } from '$lib/constants';
import { EventSourceParserStream } from 'eventsource-parser/stream';

export const getErrorMessage = (err: any, fallback = 'Server connection failed') => {
	const detail = err?.detail;
	if (typeof detail === 'string') return detail;

	return (
		detail?.error?.message ??
		detail?.message ??
		err?.error?.message ??
		err?.message ??
		(typeof err === 'string' ? err : fallback)
	);
};

export const getOpenAIConfig = async (token: string = '') => {
	let error = null;

	const res = await fetch(`${OPENAI_API_BASE_URL}/config`, {
		method: 'GET',
		headers: {
			Accept: 'application/json',
			'Content-Type': 'application/json',
			...(token && { authorization: `Bearer ${token}` })
		}
	})
		.then(async (res) => {
			if (!res.ok) throw await res.json();
			return res.json();
		})
		.catch((err) => {
			console.error(err);
			error = getErrorMessage(err);
			return null;
		});

	if (error) {
		throw error;
	}

	return res;
};

type OpenAIConfig = {
	ENABLE_OPENAI_API: boolean;
	OPENAI_API_BASE_URLS: string[];
	OPENAI_API_KEYS: string[];
	OPENAI_API_CONFIGS: object;
};

export const updateOpenAIConfig = async (token: string = '', config: OpenAIConfig) => {
	let error = null;

	const res = await fetch(`${OPENAI_API_BASE_URL}/config/update`, {
		method: 'POST',
		headers: {
			Accept: 'application/json',
			'Content-Type': 'application/json',
			...(token && { authorization: `Bearer ${token}` })
		},
		body: JSON.stringify({
			...config
		})
	})
		.then(async (res) => {
			if (!res.ok) throw await res.json();
			return res.json();
		})
		.catch((err) => {
			console.error(err);
			error = getErrorMessage(err);
			return null;
		});

	if (error) {
		throw error;
	}

	return res;
};

export const getOpenAIModelsDirect = async (url: string, key: string) => {
	let error = null;

	const res = await fetch(`${url}/models`, {
		method: 'GET',
		headers: {
			Accept: 'application/json',
			'Content-Type': 'application/json',
			...(key && { authorization: `Bearer ${key}` })
		}
	})
		.then(async (res) => {
			if (!res.ok) throw await res.json();
			return res.json();
		})
		.catch((err) => {
			error = `OpenAI: ${err?.error?.message ?? 'Network Problem'}`;
			return [];
		});

	if (error) {
		throw error;
	}

	return res;
};

export const getOpenAIModels = async (token: string, urlIdx?: number) => {
	let error = null;

	const res = await fetch(
		`${OPENAI_API_BASE_URL}/models${typeof urlIdx === 'number' ? `/${urlIdx}` : ''}`,
		{
			method: 'GET',
			headers: {
				Accept: 'application/json',
				'Content-Type': 'application/json',
				...(token && { authorization: `Bearer ${token}` })
			}
		}
	)
		.then(async (res) => {
			if (!res.ok) throw await res.json();
			return res.json();
		})
		.catch((err) => {
			error = `OpenAI: ${err?.error?.message ?? 'Network Problem'}`;
			return [];
		});

	if (error) {
		throw error;
	}

	return res;
};

export const getProviderModelCatalog = async (token: string, urlIdx: number) => {
	let error = null;

	const res = await fetch(`${OPENAI_API_BASE_URL}/models/${urlIdx}/catalog`, {
		method: 'GET',
		headers: {
			Accept: 'application/json',
			'Content-Type': 'application/json',
			...(token && { authorization: `Bearer ${token}` })
		}
	})
		.then(async (res) => {
			if (!res.ok) throw await res.json();
			return res.json();
		})
		.catch((err) => {
			error = getErrorMessage(err);
			return null;
		});

	if (error) {
		throw error;
	}

	return res;
};

export const downloadProviderModel = async (
	token: string,
	urlIdx: number,
	model: string,
	signal?: AbortSignal
) => {
	let error = null;

	const res = await fetch(`${OPENAI_API_BASE_URL}/models/${urlIdx}/download`, {
		signal,
		method: 'POST',
		headers: {
			Accept: 'application/json',
			'Content-Type': 'application/json',
			Authorization: `Bearer ${token}`
		},
		body: JSON.stringify({ model })
	})
		.then(async (res) => {
			if (!res.ok) throw await res.json();
			return res.json();
		})
		.catch((err) => {
			error = getErrorMessage(err);
			return null;
		});

	if (error) {
		throw error;
	}

	return res;
};

export const getProviderModelDownloadStatus = async (
	token: string,
	urlIdx: number,
	jobId: string,
	signal?: AbortSignal
) => {
	let error = null;

	const res = await fetch(
		`${OPENAI_API_BASE_URL}/models/${urlIdx}/download/status/${encodeURIComponent(jobId)}`,
		{
			signal,
			method: 'GET',
			headers: {
				Accept: 'application/json',
				'Content-Type': 'application/json',
				Authorization: `Bearer ${token}`
			}
		}
	)
		.then(async (res) => {
			if (!res.ok) throw await res.json();
			return res.json();
		})
		.catch((err) => {
			error = getErrorMessage(err);
			return null;
		});

	if (error) {
		throw error;
	}

	return res;
};

export type ProviderModelEvent = {
	model: string;
	event: string;
	// eslint-disable-next-line @typescript-eslint/no-explicit-any
	data?: any;
};

// Thrown by streamProviderModelEvents on a non-2xx response, carrying the
// HTTP status so callers can distinguish "this connection doesn't support
// SSE at all" (4xx -- not router mode, wrong provider, etc.; don't keep
// retrying) from a transient failure worth reconnecting for.
export class ProviderModelSseError extends Error {
	status: number;
	constructor(status: number, message: string) {
		super(message);
		this.name = 'ProviderModelSseError';
		this.status = status;
	}
}

// Consumes the llama.cpp model-management SSE stream (GET /models/{urlIdx}/sse),
// yielding one parsed event per `data: {...}` line. Each event is shaped
// { model, event, data? } -- see llama.cpp's server_models::notify_sse (events
// include model_status, status_change, download_progress, download_finished,
// download_failed, model_remove, models_reload). Used to track real download
// progress instead of assuming the fire-and-forget POST /models/{urlIdx}/download
// means "done" the instant it returns.
export async function* streamProviderModelEvents(
	token: string,
	urlIdx: number,
	signal?: AbortSignal
): AsyncGenerator<ProviderModelEvent> {
	const res = await fetch(`${OPENAI_API_BASE_URL}/models/${urlIdx}/sse`, {
		signal,
		method: 'GET',
		headers: {
			Accept: 'text/event-stream',
			Authorization: `Bearer ${token}`
		}
	});

	if (!res.ok || !res.body) {
		const detail = await res
			.json()
			.then((body) => getErrorMessage(body))
			.catch(() => `HTTP ${res.status}`);
		throw new ProviderModelSseError(res.status, detail);
	}

	const reader = res.body
		.pipeThrough(new TextDecoderStream())
		.pipeThrough(new EventSourceParserStream())
		.getReader();

	try {
		while (true) {
			const { value, done } = await reader.read();
			if (done) return;
			if (!value?.data) continue;

			try {
				yield JSON.parse(value.data);
			} catch (e) {
				console.error('Error parsing provider model SSE event:', e);
			}
		}
	} finally {
		reader.releaseLock();
	}
}

export const loadProviderModel = async (token: string, urlIdx: number, model: string) => {
	let error = null;

	const res = await fetch(`${OPENAI_API_BASE_URL}/models/${urlIdx}/load`, {
		method: 'POST',
		headers: {
			Accept: 'application/json',
			'Content-Type': 'application/json',
			Authorization: `Bearer ${token}`
		},
		body: JSON.stringify({ model })
	})
		.then(async (res) => {
			if (!res.ok) throw await res.json();
			return res.json();
		})
		.catch((err) => {
			error = getErrorMessage(err);
			return null;
		});

	if (error) {
		throw error;
	}

	return res;
};

export const unloadProviderModel = async (
	token: string,
	urlIdx: number,
	model: string,
	instanceId?: string
) => {
	let error = null;

	const res = await fetch(`${OPENAI_API_BASE_URL}/models/${urlIdx}/unload`, {
		method: 'POST',
		headers: {
			Accept: 'application/json',
			'Content-Type': 'application/json',
			Authorization: `Bearer ${token}`
		},
		body: JSON.stringify({ model, ...(instanceId ? { instance_id: instanceId } : {}) })
	})
		.then(async (res) => {
			if (!res.ok) throw await res.json();
			return res.json();
		})
		.catch((err) => {
			error = getErrorMessage(err);
			return null;
		});

	if (error) {
		throw error;
	}

	return res;
};

export const deleteProviderModel = async (token: string, urlIdx: number, model: string) => {
	let error = null;

	const res = await fetch(
		`${OPENAI_API_BASE_URL}/models/${urlIdx}?${new URLSearchParams({ model })}`,
		{
			method: 'DELETE',
			headers: {
				Accept: 'application/json',
				'Content-Type': 'application/json',
				Authorization: `Bearer ${token}`
			}
		}
	)
		.then(async (res) => {
			if (!res.ok) throw await res.json();
			return res.json();
		})
		.catch((err) => {
			error = getErrorMessage(err);
			return null;
		});

	if (error) {
		throw error;
	}

	return res;
};

export const verifyOpenAIConnection = async (
	token: string = '',
	connection: Record<string, any> = {},
	direct: boolean = false
) => {
	const { url, key, config } = connection;
	if (!url) {
		throw 'OpenAI: URL is required';
	}

	let error = null;
	let res = null;

	if (direct) {
		res = await fetch(`${url}/models`, {
			method: 'GET',
			headers: {
				Accept: 'application/json',
				Authorization: `Bearer ${key}`,
				'Content-Type': 'application/json'
			}
		})
			.then(async (res) => {
				if (!res.ok) throw await res.json();
				return res.json();
			})
			.catch((err) => {
				error = `OpenAI: ${err?.error?.message ?? 'Network Problem'}`;
				return [];
			});

		if (error) {
			throw error;
		}
	} else {
		res = await fetch(`${OPENAI_API_BASE_URL}/verify`, {
			method: 'POST',
			headers: {
				Accept: 'application/json',
				Authorization: `Bearer ${token}`,
				'Content-Type': 'application/json'
			},
			body: JSON.stringify({
				url,
				key,
				config
			})
		})
			.then(async (res) => {
				if (!res.ok) throw await res.json();
				return res.json();
			})
			.catch((err) => {
				error = `OpenAI: ${err?.error?.message ?? 'Network Problem'}`;
				return [];
			});

		if (error) {
			throw error;
		}
	}

	return res;
};

export const chatCompletion = async (
	token: string = '',
	body: object,
	url: string = `${WEBUI_BASE_URL}/api`
): Promise<[Response | null, AbortController]> => {
	const controller = new AbortController();
	let error = null;

	const res = await fetch(`${url}/chat/completions`, {
		signal: controller.signal,
		method: 'POST',
		headers: {
			Authorization: `Bearer ${token}`,
			'Content-Type': 'application/json'
		},
		body: JSON.stringify(body)
	}).catch((err) => {
		console.error(err);
		error = err;
		return null;
	});

	if (error) {
		throw error;
	}

	return [res, controller];
};

export const generateOpenAIChatCompletion = async (
	token: string = '',
	body: object,
	url: string = `${WEBUI_BASE_URL}/api`
) => {
	let error = null;

	const res = await fetch(`${url}/chat/completions`, {
		method: 'POST',
		headers: {
			Authorization: `Bearer ${token}`,
			'Content-Type': 'application/json'
		},
		credentials: 'include',
		body: JSON.stringify(body)
	})
		.then(async (res) => {
			if (!res.ok) throw await res.json();
			return res.json();
		})
		.catch((err) => {
			error = getErrorMessage(err);
			return null;
		});

	if (error) {
		throw error;
	}

	return res;
};

export const synthesizeOpenAISpeech = async (
	token: string = '',
	speaker: string = 'alloy',
	text: string = '',
	model: string = 'tts-1'
) => {
	let error = null;

	const res = await fetch(`${OPENAI_API_BASE_URL}/audio/speech`, {
		method: 'POST',
		headers: {
			Authorization: `Bearer ${token}`,
			'Content-Type': 'application/json'
		},
		body: JSON.stringify({
			model: model,
			input: text,
			voice: speaker
		})
	}).catch((err) => {
		console.error(err);
		error = err;
		return null;
	});

	if (error) {
		throw error;
	}

	return res;
};
