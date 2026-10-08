import { mount } from 'svelte';
import './app.css';
import App from './App.svelte';
import InfoPage from './InfoPage.svelte';

const page = window.location.pathname.endsWith('/privacy.html') ? 'privacy' : window.location.pathname.endsWith('/support.html') ? 'support' : null;

mount(page ? InfoPage : App, { target: document.getElementById('app'), props: page ? { page } : {} });
