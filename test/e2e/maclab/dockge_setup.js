/* Provision the first disposable Dockge account over its public Socket.IO API. */

const { io } = require('socket.io-client');

const username = process.env.DOCKGE_SETUP_USERNAME || 'cupola';
const password = process.env.DOCKGE_SETUP_PASSWORD || 'cupola-pass';
const socket = io('http://127.0.0.1:5001', {
  transports: ['websocket'],
  reconnection: false,
});

const finish = (code, message) => {
  if (message) process.stdout.write(`${message}\n`);
  socket.close();
  process.exit(code);
};

const timer = setTimeout(() => finish(1, 'Dockge setup timed out'), 10000);

socket.on('connect', () => {
  socket.emit('setup', username, password, (result) => {
    clearTimeout(timer);
    if (result?.ok === true) finish(0, 'Dockge account created');
    const message = String(result?.msg || '');
    if (
      message.includes('already been initialized') ||
      message.includes('has been initialized')
    ) {
      finish(0, 'Dockge account already exists');
    }
    finish(1, `Dockge setup failed: ${JSON.stringify(result)}`);
  });
});

socket.on('connect_error', (error) => {
  clearTimeout(timer);
  finish(1, `Dockge setup connection failed: ${error.message}`);
});
