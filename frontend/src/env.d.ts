/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** Base URL of the query API, for example a Lambda Function URL. Public value. */
  readonly VITE_API_BASE_URL?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
