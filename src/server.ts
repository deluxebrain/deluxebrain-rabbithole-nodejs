import express from 'express';

const app = express();
const port = parseInt(process.env.PORT || '3000');
const host = process.env.HOST || '127.0.0.1';

app.get('/', (req, res) => {
  res.send('Hello World!');
});

app.listen(port, host, () => {
  console.log(`server is listening on port ${port}`);
  return;
});
