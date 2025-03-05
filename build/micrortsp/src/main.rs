use anyhow::{Context, Result};
use bytes::Bytes;
use std::{
    net::{TcpListener, TcpStream},
    sync::{Arc, Mutex},
    time::Duration,
    io::{Read, Write},
    thread,
};
use tokio::sync::mpsc::{self, Sender};
use tokio::time::interval;
use v4l::prelude::*;
use v4l::FourCC;
use v4l::buffer::Type;
use v4l::io::traits::CaptureStream;

struct RtspSession {
    frames: Arc<Mutex<Vec<Bytes>>>,
    client: TcpStream,
}

impl RtspSession {
    fn new(client: TcpStream, frames: Arc<Mutex<Vec<Bytes>>>) -> Self {
        Self { client, frames }
    }

    fn handle_request(&mut self) -> Result<bool> {
        let mut buffer = [0; 4096];
        let bytes_read = self.client.read(&mut buffer)?;

        if bytes_read == 0 {
            return Ok(false); // Cliente disconnesso
        }

        let request = String::from_utf8_lossy(&buffer[..bytes_read]);
        let lines: Vec<&str> = request.lines().collect();

        if lines.is_empty() {
            return Ok(true);
        }

        let request_line = lines[0];
        let parts: Vec<&str> = request_line.split_whitespace().collect();

        if parts.len() < 3 {
            return Ok(true);
        }

        // Estrai il CSeq dalla richiesta
        let mut cseq = "1";
        for line in &lines {
            if line.starts_with("CSeq:") {
                if let Some(seq) = line.split(':').nth(1) {
                    cseq = seq.trim();
                }
            }
        }

        let method = parts[0];
        let path = parts[1];

        println!("Ricevuta richiesta: {} {}", method, path);

        match method {
            "OPTIONS" => {
                self.handle_options(cseq)?;
                Ok(true)
            },
            "DESCRIBE" => {
                self.handle_describe(cseq)?;
                Ok(true)
            },
            "SETUP" => {
                self.handle_setup(cseq, &request)?;
                Ok(true)
            },
            "PLAY" => {
                self.handle_play(cseq)?;
                Ok(true)
            },
            "TEARDOWN" => {
                self.handle_teardown(cseq)?;
                Ok(true)
            },
            _ => {
                let response = format!("RTSP/1.0 501 Not Implemented\r\nCSeq: {}\r\n\r\n", cseq);
                self.client.write_all(response.as_bytes())?;
                Ok(true)
            }
        }
    }

    fn handle_options(&mut self, cseq: &str) -> Result<()> {
        let response = format!("RTSP/1.0 200 OK\r\n\
                       CSeq: {}\r\n\
                       Public: OPTIONS, DESCRIBE, SETUP, PLAY, TEARDOWN\r\n\
                       \r\n", cseq);
        self.client.write_all(response.as_bytes())?;
        Ok(())
    }

    fn handle_describe(&mut self, cseq: &str) -> Result<()> {
        let sdp = format!("v=0\r\n\
                          o=- 0 0 IN IP4 0.0.0.0\r\n\
                          s=Micro RTSP Server\r\n\
                          c=IN IP4 0.0.0.0\r\n\
                          t=0 0\r\n\
                          m=video 0 RTP/AVP 26\r\n\
                          a=rtpmap:26 JPEG/90000\r\n\
                          a=control:track1\r\n");

        let response = format!("RTSP/1.0 200 OK\r\n\
                              CSeq: {}\r\n\
                              Content-Base: rtsp://0.0.0.0:8554/stream/\r\n\
                              Content-Type: application/sdp\r\n\
                              Content-Length: {}\r\n\
                              \r\n\
                              {}", cseq, sdp.len(), sdp);
        
        self.client.write_all(response.as_bytes())?;
        Ok(())
    }

    fn handle_setup(&mut self, cseq: &str, request: &str) -> Result<()> {
        // Estrai il Transport dalla richiesta
        let mut client_ports = (0, 0);
        for line in request.lines() {
            if line.starts_with("Transport:") {
                if let Some(transport) = line.split("client_port=").nth(1) {
                    let ports: Vec<&str> = transport.split('-').collect();
                    if ports.len() >= 2 {
                        client_ports.0 = ports[0].parse().unwrap_or(8000);
                        client_ports.1 = ports[1].split(';').next().unwrap_or("8001")
                            .parse().unwrap_or(8001);
                    }
                }
            }
        }
        
        let response = format!("RTSP/1.0 200 OK\r\n\
                       CSeq: {}\r\n\
                       Transport: RTP/AVP;unicast;client_port={}-{};server_port=9000-9001\r\n\
                       Session: 12345\r\n\
                       \r\n", cseq, client_ports.0, client_ports.1);
        self.client.write_all(response.as_bytes())?;
        Ok(())
    }

    fn handle_play(&mut self, cseq: &str) -> Result<()> {
        let response = format!("RTSP/1.0 200 OK\r\n\
                       CSeq: {}\r\n\
                       Session: 12345\r\n\
                       Range: npt=0-\r\n\
                       \r\n", cseq);
        self.client.write_all(response.as_bytes())?;
        
        // In una implementazione reale, qui inizieresti lo streaming RTP
        
        Ok(())
    }

    fn handle_teardown(&mut self, cseq: &str) -> Result<()> {
        let response = format!("RTSP/1.0 200 OK\r\n\
                       CSeq: {}\r\n\
                       Session: 12345\r\n\
                       \r\n", cseq);
        self.client.write_all(response.as_bytes())?;
        Ok(())
    }
}

async fn camera_capture_task(tx: Sender<Bytes>, frames: Arc<Mutex<Vec<Bytes>>>) -> Result<()> {
    // Apri il dispositivo video
    let dev = Device::new(0).context("Failed to open video device")?;
    
    // Configura il formato
    let mut fmt = dev.format().context("Failed to get format")?;
    fmt.width = 640;
    fmt.height = 480;
    fmt.fourcc = FourCC::new(b"YUYV");
    dev.set_format(&fmt).context("Failed to set format")?;
    
    // Configura lo streaming
    let mut stream = MmapStream::with_buffers(&dev, Type::VideoCapture, 4)
        .context("Failed to create stream")?;
    
    // Loop principale di cattura
    let mut interval = interval(Duration::from_millis(33)); // ~30fps
    
    loop {
        interval.tick().await;
        
        let cap_result = stream.next().context("Failed to get next frame");
        
        if let Ok(buffer) = cap_result {
            // Ottieni i dati dal buffer
            let bytes = buffer.to_vec();
            let frame_data = Bytes::from(bytes);
            
            // Archivia il frame più recente
            let mut frames_guard = frames.lock().unwrap();
            frames_guard.push(frame_data.clone());
            
            // Mantieni solo gli ultimi X frame
            if frames_guard.len() > 30 {
                frames_guard.remove(0);
            }
            
            // Invia il frame attraverso il canale
            if tx.send(frame_data).await.is_err() {
                break;
            }
        }
    }
    
    Ok(())
}

fn run_rtsp_server(frames: Arc<Mutex<Vec<Bytes>>>) -> Result<()> {
    let address = "0.0.0.0:8554";
    let listener = TcpListener::bind(address)?;
    println!("Server RTSP in ascolto su {}", address);

    for stream in listener.incoming() {
        match stream {
            Ok(client_stream) => {
                let client_frames = frames.clone();
                thread::spawn(move || {
                    let mut session = RtspSession::new(client_stream, client_frames);
                    while let Ok(true) = session.handle_request() {
                        // Continua a gestire richieste finché il cliente è connesso
                    }
                });
            }
            Err(e) => {
                eprintln!("Errore di connessione: {}", e);
            }
        }
    }

    Ok(())
}

#[tokio::main]
async fn main() -> Result<()> {
    // Buffer condiviso per i frame
    let frames = Arc::new(Mutex::new(Vec::new()));
    
    // Canale per passare i frame dal task di cattura
    let (tx, _rx) = mpsc::channel::<Bytes>(30);
    
    // Avvia il task di cattura in background
    let capture_frames = frames.clone();
    tokio::spawn(async move {
        if let Err(e) = camera_capture_task(tx, capture_frames).await {
            eprintln!("Errore di cattura della camera: {:?}", e);
        }
    });
    
    // Avvia il server RTSP in un thread separato
    let server_frames = frames.clone();
    run_rtsp_server(server_frames)?;
    
    Ok(())
}