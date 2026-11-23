-- 005 · Página web del panel guardada en la base.
-- El archivo fuente es panel/panel.html; se carga con db/cargar_panel.ps1 y el workflow
-- "Panel - API" lo sirve en GET /webhook/panel. Así un cambio de diseño no toca el workflow.

CREATE TABLE IF NOT EXISTS panel_recursos (
  nombre      text PRIMARY KEY,                 -- 'panel.html'
  contenido   text NOT NULL,
  actualizado timestamp NOT NULL DEFAULT now()
);
