import { WEBUI_API_BASE_URL } from '$lib/constants';

export type ModelServiceEntry = {
	name: string;
	alias: string;
	unit: string;
	port: number | null;
	path: string | null;
	size_bytes: number | null;
	active: boolean;
	state: string;
	memory_current_bytes: number | null;
	memory_peak_bytes: number | null;
};

export type SystemMemory = {
	total_bytes: number | null;
	available_bytes: number | null;
};

export type ModelServicesResponse = {
	data: ModelServiceEntry[];
	system_memory: SystemMemory;
};

export const getModelServices = async (token: string): Promise<ModelServicesResponse> => {
	let error: any = null;

	const res = await fetch(`${WEBUI_API_BASE_URL}/model-services/`, {
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
			error = err?.detail ?? 'Network Problem';
			return { data: [], system_memory: { total_bytes: null, available_bytes: null } };
		});

	if (error) {
		throw error;
	}

	return res;
};

export const startModelService = async (token: string, name: string) => {
	let error: any = null;

	const res = await fetch(
		`${WEBUI_API_BASE_URL}/model-services/${encodeURIComponent(name)}/start`,
		{
			method: 'POST',
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
			error = err?.detail ?? 'Network Problem';
			return null;
		});

	if (error) {
		throw error;
	}

	return res;
};

export const stopModelService = async (token: string, name: string) => {
	let error: any = null;

	const res = await fetch(
		`${WEBUI_API_BASE_URL}/model-services/${encodeURIComponent(name)}/stop`,
		{
			method: 'POST',
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
			error = err?.detail ?? 'Network Problem';
			return null;
		});

	if (error) {
		throw error;
	}

	return res;
};
