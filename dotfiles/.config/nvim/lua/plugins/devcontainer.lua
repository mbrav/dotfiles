return {
  {
    "esensar/nvim-dev-container",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    -- Lazy: nothing happens until a command/key is used, so the plugin is
    -- inert outside of dev container projects.
    cmd = {
      "DevcontainerStart",
      "DevcontainerAttach",
      "DevcontainerExec",
      "DevcontainerStop",
      "DevcontainerStopAll",
      "DevcontainerRemoveAll",
      "DevcontainerLogs",
      "DevcontainerEditNearestConfig",
      "DevcontainerBuild",
      "DevcontainerImageRun",
      "DevcontainerComposeUp",
      "DevcontainerComposeDown",
      "DevcontainerComposeRm",
    },
    keys = {
      { "<leader>D", "", desc = "+devcontainer" },
      { "<leader>Ds", "<cmd>DevcontainerStart<cr>", desc = "Start (build + run)" },
      { "<leader>Da", "<cmd>DevcontainerAttach<cr>", desc = "Attach" },
      { "<leader>De", ":DevcontainerExec ", desc = "Exec command" },
      { "<leader>Dx", "<cmd>DevcontainerStop<cr>", desc = "Stop" },
      { "<leader>DX", "<cmd>DevcontainerStopAll<cr>", desc = "Stop all" },
      { "<leader>Dl", "<cmd>DevcontainerLogs<cr>", desc = "Logs" },
      { "<leader>Dc", "<cmd>DevcontainerEditNearestConfig<cr>", desc = "Edit nearest devcontainer.json" },
      { "<leader>Db", "<cmd>DevcontainerBuild<cr>", desc = "Build image" },
    },
    opts = {
      -- Do not auto-start containers when opening a project; use <leader>Ds.
      autocommands = {
        init = false, -- auto-build/start on open
        clean = false, -- stop containers on VimLeave
        update = false, -- rebuild when devcontainer.json changes
      },
      -- Container runtime (this repo's tooling uses docker).
      container_runtime = "docker",
      -- Don't try to mount host nvim config/state into the container.
      attach_mounts = {
        neovim_config = { enabled = false },
        neovim_data = { enabled = false },
        neovim_state = { enabled = false },
      },
    },
  },
}
