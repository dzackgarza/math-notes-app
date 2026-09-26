// Choosing the notes root: the folder picker where the browser has one
// (Chromium), and a WebDAV server in every browser (docs/FORMAT.md, Access
// per host).
import { Button } from "@kobalte/core/button";
import { TextField } from "@kobalte/core/text-field";
import { FolderOpen } from "lucide-solid";
import { createSignal, Show } from "solid-js";

import { canPickFolder } from "../storage/folder.ts";
import { DEFAULT_WEBDAV_URL } from "../storage/store.ts";

export function Connect(props: { onChooseFolder: () => void; onConnectWebDav: (url: string) => void }) {
  const [url, setUrl] = createSignal(DEFAULT_WEBDAV_URL);
  return (
    <div class="connect">
      <Show when={canPickFolder()}>
        <Button class="button primary" onClick={() => props.onChooseFolder()}>
          <FolderOpen size={16} /> Choose notes folder
        </Button>
      </Show>
      <form
        class="row"
        onSubmit={(e) => {
          e.preventDefault();
          props.onConnectWebDav(url().trim());
        }}
      >
        <TextField value={url()} onChange={setUrl} class="field">
          <TextField.Label class="field-label">WebDAV server</TextField.Label>
          <TextField.Input class="input" />
        </TextField>
        <Button class="button" type="submit">
          Connect
        </Button>
      </form>
    </div>
  );
}
