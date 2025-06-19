const express = require('express');
const https = require('https');
const cors = require('cors'); // Re-adding CORS as per user's working setup
const ytdl = require('ytdl-core'); // Should now point to @distube/ytdl-core

const app = express();

app.use(express.json());

const YOUTUBE_MUSIC_API_HOST = 'music.youtube.com';
const YOUTUBE_API_KEY = 'AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30';

const FULL_CLIENT_CONTEXT_FOR_API = {
  client: {
    clientName: 'WEB_REMIX',
    clientVersion: '1.20250602.03.00',
    hl: 'en',
    gl: 'US',
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
    clientFormFactor: 'UNKNOWN_FORM_FACTOR',
    browserName: 'Chrome',
    browserVersion: '121.0.0.0',
    osName: 'Windows',
    osVersion: '10.0',
    platform: 'DESKTOP',
  },
  user: { lockedSafetyMode: false },
  request: {
    useSsl: true,
    internalExperimentFlags: [],
    consistencyTokenJars: []
  },
};

const USER_AGENT_HEADER = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36';

app.options('/api/youtubei/v1/:endpointName', cors());
app.options('/api/stream/:videoId', cors());

app.post('/api/youtubei/v1/:endpointName', cors(), (clientReq, clientRes) => {
  const endpointName = clientReq.params.endpointName;
  const validEndpoints = ['search', 'next', 'player', 'browse', 'get_transcript']; 

  if (!validEndpoints.includes(endpointName)) {
    console.error(`[SERVER] Error: Invalid endpoint: ${endpointName}`);
    return clientRes.status(400).json({ error: `Invalid API endpoint: ${endpointName}` });
  }

  const youtubeMusicApiPath = `/youtubei/v1/${endpointName}`;
  console.log(`[SERVER] POST to /api/youtubei/v1/${endpointName}. Forwarding to ${youtubeMusicApiPath}`);
  
  const clientSuppliedPayload = clientReq.body; 
  
  if (!clientSuppliedPayload || Object.keys(clientSuppliedPayload).length === 0) {
    console.error('[SERVER] Error: Client request body is empty.');
    return clientRes.status(400).json({ error: 'Request body from client cannot be empty.' });
  }

  const youtubeApiRequestBody = {
    context: FULL_CLIENT_CONTEXT_FOR_API,
    ...clientSuppliedPayload
  };

  const bodyString = JSON.stringify(youtubeApiRequestBody);
  console.log(`[SERVER] Body for YouTube API (${youtubeMusicApiPath}): ${bodyString.substring(0, 400) + (bodyString.length > 400 ? '...' : '')}`);

  const headersForYouTube = {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(bodyString),
    'User-Agent': USER_AGENT_HEADER,
    'X-Goog-Api-Key': YOUTUBE_API_KEY,
    'X-Youtube-Client-Name': FULL_CLIENT_CONTEXT_FOR_API.client.clientName === 'WEB_REMIX' ? '67' : '3',
    'X-Youtube-Client-Version': FULL_CLIENT_CONTEXT_FOR_API.client.clientVersion,
  };

  const options = {
    hostname: YOUTUBE_MUSIC_API_HOST,
    path: youtubeMusicApiPath,
    method: 'POST',
    headers: headersForYouTube
  };

  console.log(`[SERVER] Making POST to YouTube: https://${options.hostname}${options.path} with headers:`, Object.keys(headersForYouTube));

  const apiReq = https.request(options, (apiRes) => {
    console.log(`[SERVER] YouTube API Response Status for ${youtubeMusicApiPath}: ${apiRes.statusCode}`);
    
    let responseBodyChunks = [];
    apiRes.on('data', (chunk) => {
      responseBodyChunks.push(chunk);
    });

    apiRes.on('end', () => {
      const responseBodyBuffer = Buffer.concat(responseBodyChunks);
      const responseBodyString = responseBodyBuffer.toString('utf8');
      
      console.log(`[SERVER] YouTube API Response Body for ${youtubeMusicApiPath} (first 500 chars): ${responseBodyString.substring(0, 500) + (responseBodyString.length > 500 ? '...' : '')}`);
      
      if (apiRes.headers['content-type']) {
        clientRes.setHeader('Content-Type', apiRes.headers['content-type']);
      }
      
      clientRes.status(apiRes.statusCode).send(responseBodyBuffer);
      console.log(`[SERVER] YouTube API response for ${youtubeMusicApiPath} sent to client.`);
    });

    apiRes.on('error', (error) => {
      console.error(`[SERVER] Error receiving YouTube API response stream for ${youtubeMusicApiPath}:`, error);
      if (!clientRes.headersSent) {
        clientRes.status(500).json({ error: 'Error processing response from YouTube API.', details: error.message });
      } else {
        clientRes.end();
      }
    });
  });

  apiReq.on('error', (error) => {
    console.error(`[SERVER] Error making request to YouTube for ${youtubeMusicApiPath}:`, error);
    if (!clientRes.headersSent) {
      clientRes.status(502).json({ error: `Failed to fetch data from YouTube for ${endpointName}`, details: error.message });
    } else {
      clientRes.end();
    }
  });
  
  apiReq.on('timeout', () => {
    console.error(`[SERVER] Timeout making request to YouTube for ${youtubeMusicApiPath}.`);
    apiReq.destroy();
    if (!clientRes.headersSent) {
      clientRes.status(504).json({ error: `Timeout fetching data from YouTube for ${endpointName}.` });
    } else {
      clientRes.end();
    }
  });
  apiReq.setTimeout(15000);

  apiReq.write(bodyString);
  apiReq.end();
});

app.get('/api/image-proxy', cors(), (clientReq, clientRes) => {
  const imageUrl = clientReq.query.url;
  if (!imageUrl) {
    console.error('[SERVER] Image Proxy: URL parameter is missing.');
    return clientRes.status(400).send('URL parameter is missing');
  }

  console.log(`[SERVER] Image Proxy: Fetching image from ${imageUrl}`);

  try {
    const parsedUrl = new URL(imageUrl);
    const options = {
      hostname: parsedUrl.hostname,
      path: parsedUrl.pathname + parsedUrl.search,
      method: 'GET',
      headers: {
        'User-Agent': USER_AGENT_HEADER,
      }
    };

    const imageReq = https.request(options, (imageRes) => {
      console.log(`[SERVER] Image Proxy: Status from ${parsedUrl.hostname}: ${imageRes.statusCode}`);
      if (imageRes.statusCode === 200) {
        if (imageRes.headers['content-type']) {
          clientRes.setHeader('Content-Type', imageRes.headers['content-type']);
        }
        imageRes.pipe(clientRes);
      } else {
        clientRes.status(imageRes.statusCode).send(`Failed to fetch image. Status: ${imageRes.statusCode}`);
      }
    });

    imageReq.on('error', (error) => {
      console.error(`[SERVER] Image Proxy: Error fetching image from ${imageUrl}:`, error);
      clientRes.status(500).send(`Error fetching image: ${error.message}`);
    });
    
    imageReq.on('timeout', () => {
      console.error(`[SERVER] Image Proxy: Timeout fetching image from ${imageUrl}.`);
      imageReq.destroy();
      clientRes.status(504).send('Timeout fetching image.');
    });
    imageReq.setTimeout(10000);

    imageReq.end();

  } catch (error) {
    console.error(`[SERVER] Image Proxy: Invalid URL or error parsing URL ${imageUrl}:`, error);
    clientRes.status(400).send(`Invalid URL: ${error.message}`);
  }
});

app.get('/api/stream/:videoId', cors(), async (clientReq, clientRes) => {
  const videoId = clientReq.params.videoId;
  if (!videoId) {
    console.error('[SERVER] Stream Proxy: Video ID parameter is missing.');
    return clientRes.status(400).send('Video ID parameter is missing');
  }

  const youtubeUrl = `https://www.youtube.com/watch?v=${videoId}`;
  console.log(`[SERVER] Stream Proxy: Request for video ID: ${videoId}. URL: ${youtubeUrl}`);

  const rangeHeader = clientReq.headers.range;
  const ytdlOptions = {
    filter: 'audioonly',
    quality: 'highestaudio', // Or 'lowestaudio' for faster start, less data
    requestOptions: {
      headers: {
        'User-Agent': USER_AGENT_HEADER,
      },
    },
  };

  if (rangeHeader) {
    console.log(`[SERVER] Stream Proxy: Client requested range: ${rangeHeader}`);
    ytdlOptions.range = rangeHeader;
  }

  try {
    // Get full video info to determine total size for Content-Range header
    // ytdl.getInfo is not strictly needed if ytdl handles range response headers correctly,
    // but it's good for logging and potentially for constructing Content-Range if needed.
    // However, for simplicity and to avoid an extra request if ytdl handles it,
    // we'll rely on the 'response' event from the stream.

    const stream = ytdl(youtubeUrl, ytdlOptions);

    stream.once('response', (ytdlUpstreamResponse) => {
      // ytdlUpstreamResponse is the http.IncomingMessage from ytdl's request to YouTube
      console.log(`[SERVER] Stream Proxy: ytdl received response from YouTube. Status: ${ytdlUpstreamResponse.statusCode}`);
      console.log('[SERVER] Stream Proxy: YouTube response headers to ytdl:', JSON.stringify(ytdlUpstreamResponse.headers, null, 2));

      clientRes.setHeader('Accept-Ranges', 'bytes');
      if (ytdlUpstreamResponse.headers['content-type']) {
        clientRes.setHeader('Content-Type', ytdlUpstreamResponse.headers['content-type']);
      }

      // If client requested a range AND ytdl's request to YouTube resulted in 206 (Partial Content)
      if (rangeHeader && ytdlUpstreamResponse.statusCode === 206) {
        console.log('[SERVER] Stream Proxy: YouTube responded with 206. Setting client response to 206.');
        clientRes.status(206);
        if (ytdlUpstreamResponse.headers['content-range']) {
          clientRes.setHeader('Content-Range', ytdlUpstreamResponse.headers['content-range']);
        }
        // Content-Length for 206 should be the length of the chunk.
        // ytdl's upstream response should have this correct content-length for the partial content.
        if (ytdlUpstreamResponse.headers['content-length']) {
          clientRes.setHeader('Content-Length', ytdlUpstreamResponse.headers['content-length']);
        }
      } else if (rangeHeader && ytdlUpstreamResponse.statusCode !== 206) {
        // Client requested range, but YouTube didn't give 206 to ytdl (e.g., gave 200 with full content).
        // This means ytdl might stream the whole thing. We should inform client it's getting full content.
        console.warn(`[SERVER] Stream Proxy: Client requested range, but ytdl's request to YouTube was ${ytdlUpstreamResponse.statusCode}. Sending full stream as 200 OK.`);
        clientRes.status(200); // Send 200 OK
        if (ytdlUpstreamResponse.headers['content-length']) { // This would be total length
            clientRes.setHeader('Content-Length', ytdlUpstreamResponse.headers['content-length']);
        }
      } else {
        // No range requested by client, or ytdl is handling it and YouTube gave 200
        console.log('[SERVER] Stream Proxy: No range requested by client or full stream from YouTube. Setting client response to 200.');
        clientRes.status(200); // Default to 200 OK
        if (ytdlUpstreamResponse.headers['content-length']) {
            clientRes.setHeader('Content-Length', ytdlUpstreamResponse.headers['content-length']);
        }
      }
      
      stream.pipe(clientRes);
    });
    
    stream.on('error', (err) => {
      console.error(`[SERVER] Stream Proxy: Error during ytdl streaming for ${videoId}:`, err.message);
      if (!clientRes.headersSent) {
        clientRes.status(500).send(`Error streaming audio: ${err.message}`);
      } else {
        clientRes.end();
      }
    });

    clientReq.on('close', () => {
        console.log(`[SERVER] Stream Proxy: Client closed connection for ${videoId}. Destroying stream.`);
        stream.destroy();
    });

  } catch (error) {
    console.error(`[SERVER] Stream Proxy: Error setting up ytdl stream for ${videoId}:`, error.message);
    if (!clientRes.headersSent) {
      clientRes.status(500).send(`Error setting up audio stream: ${error.message}`);
    }
  }
});


const PORT = 8080;
app.listen(PORT, () => {
  console.log(`Custom YouTube Music API forwarder server running at http://localhost:${PORT}`);
  console.log(`Listening for POST requests on /api/youtubei/v1/:endpointName`);
  console.log(`Listening for GET requests on /api/image-proxy?url=...`);
  console.log(`Listening for GET requests on /api/stream/:videoId`);
  console.log("CORS is now handled by 'cors' middleware for preflight and main requests.");
});
