/**
 * jmrMoP Lua API Type Definitions
 *
 * This file documents all C++ functions exposed to the Lua scripting engine.
 * Use it as a reference when writing Lua plugins. Function signatures show
 * the Lua-side calling convention (not TypeScript - this is documentation only).
 *
 * Modules: console, imgui, memory, game
 */

// ---------------------------------------------------------------------------
// console
// ---------------------------------------------------------------------------

declare namespace console {
  /** Print an info message to the ImGui console. Accepts multiple arguments. */
  function log(...args: any[]): void;

  /** Alias for console.log. */
  function info(...args: any[]): void;

  /** Print a warning message (yellow) to the ImGui console. */
  function warn(...args: any[]): void;

  /** Print an error message (red) to the ImGui console. */
  function error(...args: any[]): void;

  /** Clear all console output. */
  function clear(): void;

  /** Show the console window. */
  function open(): void;

  /** Hide the console window. */
  function close(): void;

  /** Toggle console visibility. */
  function toggle(): void;
}

/**
 * Global print() is overridden to route to console.log.
 * Accepts multiple arguments, joined by tabs (matching Lua print behavior).
 */
declare function print(...args: any[]): void;

// ---------------------------------------------------------------------------
// imgui
// ---------------------------------------------------------------------------

declare namespace imgui {
  // --- Windows ---

  /**
   * Begin a new ImGui window.
   * @param name - Window title / ID.
   * @param flags - Optional ImGuiWindowFlags (default 0).
   * @returns [visible, open] - visible = window is not collapsed; open = close button not clicked.
   */
  function begin_window(name: string, flags?: number): LuaMultiReturn<[boolean, boolean]>;

  /** End the current window. Must be called after begin_window. */
  function end_window(): void;

  /**
   * Begin a child region.
   * @param id - Unique string ID.
   * @param w - Width (0 = auto).
   * @param h - Height (0 = auto).
   * @param border - Show border (default false).
   * @param flags - Optional ImGuiWindowFlags.
   * @returns true if the child is visible.
   */
  function begin_child(id: string, w?: number, h?: number, border?: boolean, flags?: number): boolean;

  /** End the current child region. */
  function end_child(): void;

  // --- Text ---

  /** Display unformatted text. */
  function text(str: string): void;

  /**
   * Display colored text.
   * @param r - Red [0..1].
   * @param g - Green [0..1].
   * @param b - Blue [0..1].
   * @param a - Alpha [0..1] (default 1).
   * @param text - The text to display.
   */
  function text_colored(r: number, g: number, b: number, a: number, text: string): void;

  /** Display word-wrapped text. */
  function text_wrapped(str: string): void;

  /** Display a label + text pair. */
  function label_text(label: string, text: string): void;

  /** Display bulleted text. */
  function bullet_text(str: string): void;

  // --- Buttons ---

  /**
   * Render a button.
   * @param label - Button text.
   * @param w - Width (0 = auto).
   * @param h - Height (0 = auto).
   * @returns true if clicked.
   */
  function button(label: string, w?: number, h?: number): boolean;

  /** Small button without frame padding. */
  function small_button(label: string): boolean;

  /**
   * Checkbox.
   * @param label - Checkbox label.
   * @param value - Current checked state.
   * @returns [changed, new_value].
   */
  function checkbox(label: string, value: boolean): LuaMultiReturn<[boolean, boolean]>;

  /**
   * Radio button.
   * @param label - Button label.
   * @param active - Whether this option is currently selected.
   * @returns true if clicked.
   */
  function radio_button(label: string, active: boolean): boolean;

  // --- Sliders / Drags / Inputs ---

  /**
   * Float slider.
   * @returns [changed, new_value].
   */
  function slider_float(label: string, value: number, min: number, max: number, format?: string): LuaMultiReturn<[boolean, number]>;

  /**
   * Integer slider.
   * @returns [changed, new_value].
   */
  function slider_int(label: string, value: number, min: number, max: number): LuaMultiReturn<[boolean, number]>;

  /**
   * Drag float.
   * @param speed - Drag speed (default 1.0).
   * @returns [changed, new_value].
   */
  function drag_float(label: string, value: number, speed?: number, min?: number, max?: number): LuaMultiReturn<[boolean, number]>;

  /**
   * Drag integer.
   * @returns [changed, new_value].
   */
  function drag_int(label: string, value: number, speed?: number, min?: number, max?: number): LuaMultiReturn<[boolean, number]>;

  /**
   * Single-line text input.
   * @param label - Input label.
   * @param current - Current text value.
   * @param flags - Optional ImGuiInputTextFlags.
   * @returns [changed, new_text].
   */
  function input_text(label: string, current?: string, flags?: number): LuaMultiReturn<[boolean, string]>;

  /**
   * Integer input.
   * @returns [changed, new_value].
   */
  function input_int(label: string, value: number): LuaMultiReturn<[boolean, number]>;

  /**
   * Float input.
   * @returns [changed, new_value].
   */
  function input_float(label: string, value: number): LuaMultiReturn<[boolean, number]>;

  // --- Color ---

  /**
   * RGB color editor.
   * @returns [changed, r, g, b].
   */
  function color_edit3(label: string, r: number, g: number, b: number): LuaMultiReturn<[boolean, number, number, number]>;

  /**
   * RGBA color editor.
   * @returns [changed, r, g, b, a].
   */
  function color_edit4(label: string, r: number, g: number, b: number, a?: number): LuaMultiReturn<[boolean, number, number, number, number]>;

  /**
   * Convert RGBA floats [0..1] to a packed ImU32 color value.
   * @returns Packed color as integer.
   */
  function color_u32(r: number, g: number, b: number, a?: number): number;

  // --- Trees / Collapsing ---

  /** Begin a tree node. Returns true if open (call tree_pop if true). */
  function tree_node(label: string): boolean;

  /** Pop a tree node. */
  function tree_pop(): void;

  /** Collapsing header. Returns true if open. */
  function collapsing_header(label: string, flags?: number): boolean;

  // --- Selectables / Combo ---

  /**
   * Selectable item.
   * @returns [clicked, selected].
   */
  function selectable(label: string, selected?: boolean, flags?: number): LuaMultiReturn<[boolean, boolean]>;

  /** Begin a combo box. Returns true if open (call end_combo if true). */
  function begin_combo(label: string, preview: string): boolean;

  /** End the combo box. */
  function end_combo(): void;

  // --- Tabs ---

  /** Begin a tab bar. Returns true if visible. */
  function begin_tab_bar(id: string): boolean;

  /** End the tab bar. */
  function end_tab_bar(): void;

  /**
   * Begin a tab item.
   * @returns [visible, open].
   */
  function begin_tab_item(label: string): LuaMultiReturn<[boolean, boolean]>;

  /** End the tab item. */
  function end_tab_item(): void;

  // --- Tables ---

  /** Begin a table. Returns true if visible. */
  function begin_table(id: string, columns: number, flags?: number): boolean;

  /** End the table. */
  function end_table(): void;

  /** Setup a table column header. */
  function table_setup_column(label: string, flags?: number, init_width?: number): void;

  /** Render column headers row. */
  function table_headers_row(): void;

  /** Advance to the next table row. */
  function table_next_row(): void;

  /** Advance to the next table column. Returns true if visible. */
  function table_next_column(): boolean;

  /** Set the current column index. Returns true if visible. */
  function table_set_column_index(index: number): boolean;

  // --- Popups / Modals ---

  /** Open a popup by name. */
  function open_popup(name: string): void;

  /** Begin a popup. Returns true if open. */
  function begin_popup(name: string): boolean;

  /**
   * Begin a modal popup.
   * @returns [visible, open].
   */
  function begin_popup_modal(name: string): LuaMultiReturn<[boolean, boolean]>;

  /** End the popup. */
  function end_popup(): void;

  /** Close the current popup. */
  function close_current_popup(): void;

  // --- Layout ---

  /** Horizontal separator line. */
  function separator(): void;

  /** Place the next widget on the same line. */
  function same_line(offset?: number, spacing?: number): void;

  /** Add vertical spacing. */
  function spacing(): void;

  /** Indent content. */
  function indent(width?: number): void;

  /** Unindent content. */
  function unindent(width?: number): void;

  /** Add an invisible widget of a given size. */
  function dummy(w: number, h: number): void;

  /** Force a new line. */
  function new_line(): void;

  // --- Tooltips ---

  /** Begin a tooltip region. */
  function begin_tooltip(): void;

  /** End the tooltip region. */
  function end_tooltip(): void;

  /** Show a simple tooltip with text. */
  function set_tooltip(text: string): void;

  // --- Item State ---

  /** Returns true if the last item is hovered. */
  function is_item_hovered(): boolean;

  /** Returns true if the last item was clicked. */
  function is_item_clicked(button?: number): boolean;

  /** Returns true if the last item is active (held). */
  function is_item_active(): boolean;

  // --- Style ---

  /** Push a style color. Use ImGuiCol_* constants for idx. */
  function push_style_color(idx: number, r: number, g: number, b: number, a?: number): void;

  /** Pop style color(s). */
  function pop_style_color(count?: number): void;

  /** Push a float style variable. Use ImGuiStyleVar_* constants for idx. */
  function push_style_var(idx: number, value: number): void;

  /** Push a vec2 style variable. */
  function push_style_var_vec2(idx: number, x: number, y: number): void;

  /** Pop style variable(s). */
  function pop_style_var(count?: number): void;

  // --- IO ---

  /** Get current mouse position. @returns [x, y]. */
  function get_mouse_pos(): LuaMultiReturn<[number, number]>;

  /** Returns true if a mouse button was clicked this frame. */
  function is_mouse_clicked(button?: number): boolean;

  /** Returns true if a key was pressed this frame. Use ImGuiKey_* constants. */
  function is_key_pressed(key: number): boolean;

  /** Get display/viewport size. @returns [width, height]. */
  function get_display_size(): LuaMultiReturn<[number, number]>;

  /** Get current framerate (frames per second). */
  function get_framerate(): number;

  // --- DrawList (Background) ---

  /** Draw a line on the background draw list. */
  function draw_line(x1: number, y1: number, x2: number, y2: number, color: number, thickness?: number): void;

  /** Draw a rectangle outline on the background draw list. */
  function draw_rect(x1: number, y1: number, x2: number, y2: number, color: number, rounding?: number, thickness?: number): void;

  /** Draw a filled rectangle on the background draw list. */
  function draw_rect_filled(x1: number, y1: number, x2: number, y2: number, color: number, rounding?: number): void;

  /** Draw a circle outline on the background draw list. */
  function draw_circle(cx: number, cy: number, radius: number, color: number, segments?: number, thickness?: number): void;

  /** Draw a filled circle on the background draw list. */
  function draw_circle_filled(cx: number, cy: number, radius: number, color: number, segments?: number): void;

  /** Draw a filled triangle on the background draw list. */
  function draw_triangle_filled(x1: number, y1: number, x2: number, y2: number, x3: number, y3: number, color: number): void;

  /** Draw a filled quad on the background draw list. Vertices should be in order (CW or CCW). */
  function draw_quad_filled(x1: number, y1: number, x2: number, y2: number, x3: number, y3: number, x4: number, y4: number, color: number): void;

  /** Draw text on the background draw list. */
  function draw_text(x: number, y: number, color: number, text: string): void;

  // --- Utility ---

  /** Set the position of the next window. */
  function set_next_window_pos(x: number, y: number, cond?: number): void;

  /** Set the size of the next window. */
  function set_next_window_size(w: number, h: number, cond?: number): void;

  /** Render a progress bar. */
  function progress_bar(fraction: number, overlay?: string): void;

  /** Get elapsed time since ImGui initialization (seconds). */
  function get_time(): number;

  /**
   * Scroll the current window/child so the current cursor position is visible.
   * @param center_y_ratio - 0.0 = top, 0.5 = center, 1.0 = bottom (default 0.5).
   */
  function set_scroll_here_y(center_y_ratio?: number): void;

  /** Get current vertical scroll position. */
  function get_scroll_y(): number;

  /** Get maximum vertical scroll position. */
  function get_scroll_max_y(): number;

  /** Set the background alpha for the next window. */
  function set_next_window_bg_alpha(alpha: number): void;
}

// ---------------------------------------------------------------------------
// cleu
// ---------------------------------------------------------------------------

/** Combat Log Event data returned by cleu.poll(). */
interface CLEUEvent {
  subevent: string;
  timestamp: number;
  source_guid: string;
  source_name: string;
  source_flags: number;
  source_raid_flags: number;
  dest_guid: string;
  dest_name: string;
  dest_flags: number;
  dest_raid_flags: number;
  spell_id: number;
  suffix_flags: number;
  amount: number;
  school: number;
  resisted: number;
  blocked: number;
  absorbed: number;
  critical: number;
  overheal: number;
  aura_type: "BUFF" | "DEBUFF" | null;
}

declare namespace cleu {
  /** Poll pending CLEU events. Returns an array of event tables. */
  function poll(): CLEUEvent[];

  /** Total events captured since initialization. */
  function event_count(): number;

  /** Whether the CLEU capture system is active. */
  function active(): boolean;

  /** Number of events dropped due to buffer overflow. */
  function drop_count(): number;
}

// ---------------------------------------------------------------------------
// packet — Network packet capture
// ---------------------------------------------------------------------------

/** A captured network packet returned by packet.poll(). */
interface CapturedPacket {
  /** "RECV" for incoming, "SEND" for outgoing. */
  dir: "RECV" | "SEND";
  /** Monotonically increasing sequence number. */
  seq: number;
  /** Capture timestamp in milliseconds (steady_clock). */
  timestamp: number;
  /** 32-bit opcode as an 8-char hex string, e.g. "00330001". */
  opcode: string;
  /** Total payload size in bytes (opcode + body). */
  size: number;
  /** Raw payload bytes as a hex string, e.g. "0A 3B FF 00 ...". */
  hex: string;
}

declare namespace packet {
  /**
   * Poll newly captured packets since the last call.
   * Returns an array of packet tables. Non-destructive per frame —
   * each call drains the pending buffer.
   */
  function poll(): CapturedPacket[];

  /**
   * Get capture statistics.
   * @returns Table with recv_count, send_count, recv_bytes, send_bytes, total.
   */
  function stats(): {
    recv_count: number;
    send_count: number;
    recv_bytes: number;
    send_bytes: number;
    total: number;
  };

  /** Clear the internal packet buffer. */
  function clear(): void;

  /** Pause packet capture (packets are still intercepted but not stored). */
  function pause(): void;

  /** Resume packet capture after a pause. */
  function resume(): void;

  /** Check whether capture is currently paused. */
  function is_paused(): boolean;

  /** Whether the packet hooks are installed and active. */
  function active(): boolean;

  /**
   * Set the maximum number of packets kept in the internal buffer.
   * Oldest packets are evicted when the limit is reached.
   */
  function set_max_packets(n: number): void;

  /**
   * Set the maximum number of bytes captured per packet.
   * Packets larger than this are truncated.
   */
  function set_capture_bytes(n: number): void;
}

// ---------------------------------------------------------------------------
// memory
// ---------------------------------------------------------------------------

declare namespace memory {
  /** Get the base address of WowClassic.exe. */
  function get_base(): number;

  /** Read an unsigned 8-bit value at address. */
  function read_u8(address: number): number;

  /** Read an unsigned 16-bit value at address. */
  function read_u16(address: number): number;

  /** Read an unsigned 32-bit value at address. */
  function read_u32(address: number): number;

  /** Read an unsigned 64-bit value at address. */
  function read_u64(address: number): number;

  /** Read a signed 32-bit value at address. */
  function read_i32(address: number): number;

  /** Read a 32-bit float at address. */
  function read_float(address: number): number;

  /** Read a 64-bit double at address. */
  function read_double(address: number): number;

  /** Read a pointer-sized value at address. */
  function read_ptr(address: number): number;

  /**
   * Read a null-terminated string at address.
   * @param address - Memory address.
   * @param max_len - Maximum bytes to read (default 256, max 1024).
   * @returns The string, or nil if unreadable.
   */
  function read_string(address: number, max_len?: number): string | null;

  /**
   * Write an unsigned 8-bit value at address.
   * @returns true on success.
   */
  function write_u8(address: number, value: number): boolean;

  /**
   * Write an unsigned 32-bit value at address.
   * @returns true on success.
   */
  function write_u32(address: number, value: number): boolean;

  /**
   * Write a 32-bit float at address.
   * @returns true on success.
   */
  function write_float(address: number, value: number): boolean;
}

// ---------------------------------------------------------------------------
// game — Object Manager & Entity Access
// ---------------------------------------------------------------------------

/** Unit-specific data, present when entity has the Unit ECS tag. */
interface UnitDataSnapshot {
  health?: number;
  max_health?: number;
  level?: number;
  name?: string;
  unit_flags?: number;
  /** UNIT_FIELD_FLAGS3 bitmask (e.g. bit 30 = UNK30 for extra bounding radius). */
  unit_flags3?: number;
  /** Model hitbox radius (float, from CGUnit descriptor). */
  bounding_radius?: number;
  /** Melee combat reach (float, default 1.333f for humanoids). */
  combat_reach?: number;
  power?: number;
  max_power?: number;
  power_type?: number;
  /** Default power slot index. */
  default_slot?: number;
  /** Array of all power slots with current/max/type for each. */
  powers?: Array<{ index: number; current: number; max: number; type: number }>;
  speed?: number;
  entry_id?: number;
  /** Dynamic flags from entity descriptor + 0xCC. Bit 4 (0x10) = tap denied. */
  dynamic_flags?: number;
  race?: number;
  class_id?: number;
  gender?: number;
  /** Classification: 0=normal, 1=elite, 2=rareelite, 3=worldboss, 4=rare, 5=trivial, 6=minus. */
  classification?: number;
  /** Classification as string: "normal", "elite", "rareelite", "worldboss", "rare", "trivial", "minus". */
  classification_name?: string;
  /** Array of aura info objects (buffs/debuffs). */
  auras?: Array<{ spell_id: number; name?: string }>;
  /** True if health <= 0. */
  is_dead: boolean;
  /** True if entity is a player (not NPC). */
  is_player: boolean;
  /** True if UNIT_FLAG_IN_COMBAT (0x00080000) is set. */
  in_combat: boolean;
  /** True if mount display ID > 0 and no override flag (from IsMounted sub_27B8DE0). */
  is_mounted: boolean;
  /** Mount display ID (> 0 when mounted). Only set when is_mounted is true. */
  mount_display_id?: number;
  /** True if the unit is currently casting (has a cast bar). */
  is_casting: boolean;
  /** Spell ID being cast (only set when is_casting is true). */
  casting_spell_id?: number;
  /** Name of the spell being cast (only set when is_casting is true). */
  casting_spell_name?: string;
  /** True if the unit is channeling a spell. */
  is_channeling: boolean;
  /**
   * True if the local player is swimming. Only populated for the active player.
   * Always false for non-player entities.
   */
  is_swimming: boolean;
  /**
   * Active specialization index (1-based, matching WoW API convention).
   * Only populated for the active player. 1-4 depending on class.
   * Absent if spec could not be resolved.
   */
  spec_id?: number;
  /**
   * Human-readable specialization name (e.g. "Beast Mastery", "Holy").
   * Only present when spec_id is present and class is known.
   */
  spec_name?: string;
  /** Bitmask of which fields were successfully read. */
  valid_fields: number;
  /** Descriptor parent pointer for the Unit component (if resolved). */
  unit_parent?: number;
  /** Descriptor parent pointer for the Player component (if resolved). */
  player_parent?: number;
}

/** An entity snapshot returned by game.objects() / game.local_player(). */
interface GameEntity {
  obj_ptr: number;
  /** CGUnit accessor pointer (read from obj_ptr + 0x28). Used by unit_* functions internally. */
  cgunit: number;
  comp_table: number;
  slot: number;
  class: string;
  guid: string;
  /** Lower 64 bits of the 128-bit GUID (for reaction/cast_at functions). */
  guid_lo: number;
  /** Upper 64 bits of the 128-bit GUID (for reaction/cast_at functions). */
  guid_hi: number;
  /** Entity name (from ECS name component). May be absent for some entity types. */
  name?: string;
  tags: string[];
  position?: { x: number; y: number; z: number };
  server_position?: { x: number; y: number; z: number };
  facing?: number;
  /** Creature/gameobject entry ID from descriptor + 0xC8. Present for Unit and GameObject entities. */
  entry_id?: number;
  /** Dynamic flags from descriptor + 0xCC (tap/loot state). Bit 4 (0x10) = tap denied. */
  dynamic_flags?: number;

  // -- GO descriptor fields (present for GameObject entities) --
  /** GO type ID from BYTES_1 byte 1 (e.g. 3=chest, 10=goober). */
  go_type?: number;
  /** GO state from BYTES_1 byte 0 (0=ready, 1=active, 2=destroyed). */
  go_state?: number;
  go_display_id?: number;
  go_flags?: number;
  go_faction?: number;
  /** Quest ID from type-specific data block (universal prop 0x14). */
  go_quest_id?: number;
  /** Loot table ID from type-specific data block (universal prop 0x06). */
  go_loot_id?: number;
  /** Lock ID from type-specific data block (universal prop 0x04). */
  go_lock_id?: number;
  /** Event ID triggered on interact (prop 0x0D chest / 0x15 goober). */
  go_event_id?: number;
  /** Entry ID of a linked trap GO (prop 0x1E). */
  go_linked_trap_id?: number;
  /** Gossip menu ID for goober-type GOs (prop 0x26). */
  go_gossip_id?: number;
  /** Condition ID for visibility/interaction gating (prop 0x55). */
  go_condition_id?: number;
  /** Spell cast on interact (prop 0x0A). */
  go_spell_id?: number;

  /** Unit-specific data (health, level, flags, etc.). Present for Unit/Player/ActivePlayer. */
  unit?: UnitDataSnapshot;
}

/** A raw descriptor field entry from game.descriptor_fields(). */
interface DescriptorFieldEntry {
  offset: number;
  i32: number;
  u32: number;
  f32: number;
}

declare namespace game {
  /** Get the game module base address. */
  function get_base(): number;

  /**
   * Get all entities, optionally filtered by class name.
   * @param class_filter - "Unit", "Player", "GameObject", etc. Omit for all.
   * @returns Array of entity tables (snapshot from current frame).
   */
  function objects(class_filter?: string): GameEntity[];

  /**
   * Count entities, optionally filtered by class name.
   * @param class_filter - Omit for total count.
   */
  function object_count(class_filter?: string): number;

  /**
   * Get the local player entity (ActivePlayer).
   * @returns Entity table, or nil if not logged in.
   */
  function local_player(): GameEntity | null;

  /** Force an Object Manager refresh (normally auto per-frame). Returns new entity count. */
  function refresh_objects(): number;

  /**
   * Check if an entity has a specific ECS tag.
   * @param obj_ptr - Entity object pointer.
   * @param tag_id - Tag ID (use game.TAG.* constants).
   */
  function has_tag(obj_ptr: number, tag_id: number): boolean;

  /**
   * Resolve a component's raw data pointer from the entity's inline slot array.
   * @param obj_ptr - Entity object pointer.
   * @param tag_id - ECS tag/component ID (use game.TAG.* constants).
   * @returns Data pointer for use with memory.read_*, or nil if absent.
   */
  function component_data(obj_ptr: number, tag_id: number): number | null;

  /**
   * Get 3D world position for an entity.
   * @param obj_ptr - Entity object pointer.
   * @returns x, y, z on success; nil on failure.
   */
  function entity_position(obj_ptr: number): LuaMultiReturn<[number, number, number]> | null;

  /**
   * Get facing angle for an entity.
   * @param obj_ptr - Entity object pointer.
   * @returns facing angle in radians, or nil on failure.
   */
  function entity_facing(obj_ptr: number): number | null;

  /**
   * Read a C++ vtable from an object pointer.
   * First qword at ptr is the vtable pointer. Entries validated against module range.
   * @param ptr - Object pointer (vtable is at *(ptr+0)).
   * @param max_entries - Maximum entries to read (default 200).
   * @returns Array of {index, rva}, or nil if ptr has no valid vtable.
   */
  function read_vtable(ptr: number, max_entries?: number): Array<{index: number; rva: number}> | null;

  /**
   * Read raw bytes from a function address.
   * @param addr - Absolute address of the function.
   * @param max_bytes - Maximum bytes to read (default 512, max 4096).
   * @param cc_terminate - Stop at CC CC padding (default true).
   * @returns Space-separated hex string ("48 89 5C 24 08"), or nil.
   */
  function read_func_bytes(addr: number, max_bytes?: number, cc_terminate?: boolean): string | null;

  /**
   * Enumerate all components on an entity via its comp_table and inline slot array.
   * @param obj_ptr - Entity object pointer.
   * @returns Array of component info tables, or nil on failure.
   */
  function entity_components(obj_ptr: number): Array<{
    tag_id: number;
    name: string;
    comp_idx: number;
    type_ptr: number;
    data_ptr: number;
  }> | null;

  /**
   * Project world coordinates to screen coordinates via the camera VP matrix.
   * Returns screen x, y on success; nil if the point is behind the camera.
   */
  function world_to_screen(x: number, y: number, z: number): LuaMultiReturn<[number, number]> | null;

  /**
   * Read raw descriptor fields from a component's parent area.
   * Returns int32, uint32, and float interpretations for each 4-byte slot.
   * Use to discover field offsets empirically.
   * @param obj_ptr - Entity object pointer.
   * @param tag_id - ECS tag/component ID (0=CGObject, 5=Unit, 6=Player, 112=FEntityPos).
   * @param count - Number of 4-byte fields to read (default 256, max 2048).
   */
  function descriptor_fields(obj_ptr: number, tag_id: number, count?: number): DescriptorFieldEntry[] | null;

  /**
   * Resolve a component descriptor's parent pointer.
   * @param obj_ptr - Entity object pointer.
   * @param tag_id - ECS tag/component ID.
   * @returns Parent pointer (descriptor field data area), or nil.
   */
  function descriptor_parent(obj_ptr: number, tag_id: number): number | null;

  /** Check if a player is logged in (ActivePlayer entity exists). */
  function is_logged_in(): boolean;

  // ---- Spell Book APIs ----

  /**
   * Check if the local player knows a spell by ID.
   * Pure memory read — walks the chained hash set.
   * @param spell_id - The numeric spell ID to check.
   */
  function is_spell_known(spell_id: number): boolean;

  /**
   * Get all known spell IDs for the local player.
   * @param with_names - If true, returns {id, name?}[] instead of number[].
   */
  function known_spells(with_names?: false): number[];
  function known_spells(with_names: true): Array<{ id: number; name?: string }>;

  /**
   * Get the count of known spells.
   */
  function known_spell_count(): number;

  /**
   * Get pet spell IDs/names.
   * @param with_names - If true, returns {id, type, name?}[] instead of number[].
   */
  function pet_spells(with_names?: false): number[];
  function pet_spells(with_names: true): Array<{ id: number; type: number; name?: string }>;

  /**
   * Get spell book UI entries with slot index and hidden flag.
   * @param with_names - If true, includes name field.
   */
  function spell_book_entries(with_names?: boolean): Array<{
    id: number;
    slot: number;
    hidden: boolean;
    name?: string;
  }>;

  /**
   * Diagnostic info about the spell book hash table.
   */
  function spell_book_debug(): {
    initialized: boolean;
    hash_table_base: number;
    hash_table_rva?: number;
    bucket_count: number;
    spell_count: number;
  };

  // ---- Targeting ----

  /** Target info returned by target / soft_enemy / soft_friend / soft_interact. */
  interface TargetInfo {
    guid: string;
    name: string;
  }

  /** Get the player's current hard target. Returns nil if no target. */
  function target(): TargetInfo | null;

  /** Get the soft-enemy target (mouseover hostile). */
  function soft_enemy(): TargetInfo | null;

  /** Get the soft-friend target (mouseover friendly). */
  function soft_friend(): TargetInfo | null;

  /** Get the soft-interact target (mouseover interactable). */
  function soft_interact(): TargetInfo | null;

  /**
   * Interact with an entity directly, without setting target.
   * Calls the entity's native interact virtual function (vtable +328).
   * Works for NPCs, GameObjects, and other interactable entities.
   * @param obj_ptr - Entity object pointer (from entity.obj_ptr).
   * @returns true if the interact call executed, false on failure.
   */
  function interact(obj_ptr: number): boolean;

  /**
   * Check if the player can interact with an entity.
   * Checks two conditions from the game's InteractDispatch (sub_2291CA0):
   *   1. Player gate: player is not dead/ghost/incapacitated.
   *   2. Entity blocker: entity's interaction is not suppressed at runtime.
   * Does NOT check range — use game.distance() for that.
   * @param obj_ptr - Entity object pointer.
   * @returns true if interaction is allowed, false if blocked.
   */
  function can_interact(obj_ptr: number): boolean;

  /**
   * Read the game's 5-tier interact distance table (from sub_279B4A0).
   * Returns actual distances in yards (sqrt of the internal squared values).
   * Indices (1-based): 1=Inspect, 2=Trade, 3=Duel, 4=Follow, 5=Interact.
   * @returns Array of 5 floats (yards) indexed 1-5.
   */
  function interact_distances(): number[];

  /**
   * Check if the player is within interact distance of an entity.
   * Reimplements the game's CheckInteractDistance (sub_279B4A0) using our
   * own position data (bypasses ResolveAccessor which fails from injected).
   * Computes 3D squared distance and compares against the game's distance
   * table at flt_34DF7D8[index].
   * @param obj_ptr - Entity object pointer.
   * @param dist_index - 1-based distance tier: 1=Inspect, 2=Trade, 3=Duel, 4=Follow, 5=Interact.
   * @returns true if within the specified distance tier.
   */
  function check_interact_distance(obj_ptr: number, dist_index: number): boolean;

  /**
   * Read any type-specific property from a GameObject's data block.
   * Uses the type descriptor table (sub_20A5D70) to map property IDs to
   * data slot indices. Returns nil if the entity is not a GO or the
   * property doesn't exist for that GO type.
   * @param obj_ptr - Entity object pointer.
   * @param property_id - Universal property ID (0-261). See go_prop:: constants.
   *   Common: 0x04=lockId, 0x06=lootId, 0x14=questId, 0x55=conditionId.
   */
  function go_data(obj_ptr: number, property_id: number): number | null;

  /**
   * Get the current mouseover unit (entity under the mouse cursor).
   * Reads the 128-bit mouseover GUID (pattern-scanned at runtime).
   */
  function mouseover(): TargetInfo | null;

  /**
   * Get the current focus unit.
   * Reads the 128-bit focus GUID (pattern-scanned at runtime) and
   * resolves the name via the entity cache.
   */
  function focus(): TargetInfo | null;

  /**
   * Set the focus to an entity by its obj_ptr. Writes the entity's GUID
   * directly to the focus global (bypasses game validation/accessors
   * which fail from injected context).
   * @param obj_ptr - Entity object pointer.
   * @returns true if the focus was set, false if obj_ptr not found.
   */
  function set_focus(obj_ptr: number): boolean;

  /**
   * Clear the current focus (writes zero GUID to the focus global).
   */
  function clear_focus(): void;

  // ---- Map / Zone ----

  /** Get the current map ID. Returns 0 if unavailable. */
  function map_id(): number;

  /** Get the current zone name. Returns nil if unavailable. */
  function zone_name(): string | null;

  /** Get the current subzone name. Returns nil if unavailable. */
  function subzone_name(): string | null;

  // ---- Quest System ----

  /** Quest objective info as returned inside quest_log() entries. */
  interface QuestObjective {
    /** Objective record ID from the quest database. */
    id: number;
    /**
     * Objective type enum:
     *   0=creature(kill), 1=item, 2=object, 3=creature(alt), 4=currency,
     *   5=spell, 6/7/0x12=reputation, 8=money, 9/0xD=player(PvP),
     *   0xA-0xE/0x13/0x14=event, 0xF=progressbar
     */
    type: number;
    /** Entry ID of the creature/item/object/spell this objective tracks. */
    target_id: number;
    /** Number of kills/items/interactions required to complete this objective. */
    required: number;
    /** Objective flags bitmask. Bit 0 (0x01) = hidden, Bit 3 (0x08) = hidden. */
    flags: number;
    /** Objective description text from game data (may be empty for some objectives). */
    description?: string;
    /** Human-readable type: "creature","item","object","event","spell","reputation",etc. */
    type_str: string;
    /** Storage index within the tracking slot's progress array (used for memory reads). */
    storage_index: number;
    /** True if this objective is optional (not required for quest completion). */
    is_optional: boolean;
    /**
     * Current progress count for this objective.
     * Only present when the parent quest's `has_progress` is true.
     * For kill/interact types, read from the player's tracking slot.
     * For item types, counted from player inventory.
     */
    progress?: number;
  }

  /** Quest info as returned by quest_log(). */
  interface QuestEntry {
    quest_id: number;
    quest_slot: number;
    quest_flags: number;
    quest_type: number;
    log_flags: number;
    /** Number of objectives for this quest. */
    objective_count: number;
    /** Quest name from game data. May be absent if name resolution failed. */
    quest_name?: string;
    objectives: QuestObjective[];
    /** True if the quest's tracking slot was found in the player's tracking array. */
    has_progress: boolean;
    /** Debug string describing progress resolution status (e.g. "ok", "not_in_tracking:qid=XXX"). */
    progress_debug?: string;
    /** Raw 72-byte tracking slot as a hex string (144 chars). Only present when has_progress is true. */
    raw_slot_hex?: string;
  }

  /** Target entry from quest_targets(). */
  interface QuestTargetEntry {
    quest_id: number;
    obj_idx: number;
    required: number;
    obj_type: number;
  }

  /** Target maps returned by quest_targets(). Keys are entry_id numbers. */
  interface QuestTargetMaps {
    creatures: { [entry_id: number]: QuestTargetEntry[] };
    objects: { [entry_id: number]: QuestTargetEntry[] };
    items: { [entry_id: number]: QuestTargetEntry[] };
  }

  /**
   * Get all active quests from the quest log with their objectives.
   * Reads quest log entries and quest records from game memory.
   * Only returns quests whose data is fully loaded (state_flags & 1).
   *
   * The returned array also has a `tracking_diag` string field (accessed
   * as `result.tracking_diag`) containing diagnostic info about the
   * player's quest tracking memory layout.
   */
  function quest_log(): QuestEntry[] & { tracking_diag?: string };

  /**
   * Get target maps for entity→quest matching.
   * Returns creature, object, and item target maps keyed by entry_id.
   * Each value is an array of quest targets that require that entity.
   */
  function quest_targets(): QuestTargetMaps;

  /** Get the number of active quests in the quest log. */
  function quest_count(): number;

  /**
   * Low-level diagnostic for debugging quest data reading.
   * Returns a table with memory addresses, raw entry dumps, hash table state,
   * and first-quest lookup results. Primarily for development/troubleshooting.
   */
  function quest_debug(): {
    base: number;
    error?: string;
    count_addr: number;
    log_count: number;
    entries_addr: number;
    bucket_count: number;
    hash_mask: number;
    hash_buckets: number;
    raw_entries: Array<{
      dword0: number; dword1: number; dword2: number;
      byte12: number; byte13: number; byte14: number;
    }>;
    first_quest_id?: number;
    bucket_idx?: number;
    first_node?: number;
    node_key?: number;
    state_flags?: number;
    obj_count?: number;
  };

  // ---- Object Manager Toggles ----

  /**
   * Get or set a specific OM function toggle by name.
   * If value is omitted, returns the current state.
   * If value is provided, sets it and returns the new state.
   * Valid names: "position", "facing", "level", "health", "max_health",
   *              "name", "unit_name", "map_id", "spell_name", "auras".
   */
  function om_toggle(name: string, value?: boolean): boolean;

  /**
   * Get all OM toggle states as a table.
   * If a boolean is passed, sets ALL toggles to that value first.
   */
  function om_toggles(set_all?: boolean): Record<string, boolean>;

  /**
   * Get all pattern-scanned addresses as a table of { name = rva, ... }.
   * Useful for siggen/IDA cross-referencing.
   */
  function resolved_addresses(): Record<string, number>;

  // ---- Entity Bounds / Camera ----

  /** Bounding box data returned by entity_bounds. */
  interface BoundingBoxInfo {
    min_x: number; min_y: number; min_z: number;
    max_x: number; max_y: number; max_z: number;
    width: number; height: number; depth: number;
  }

  /**
   * Get the axis-aligned bounding box for an entity.
   * @param obj_ptr - Entity object pointer.
   * @returns Bounding box table, or nil if unavailable.
   */
  function entity_bounds(obj_ptr: number): BoundingBoxInfo | null;

  /**
   * Get camera debug info (pointer, position, VP matrix rows).
   * @returns Camera info table, or nil if unavailable.
   */
  function camera_debug(): Record<string, any> | null;

  // ---- Spell Casting APIs ----
  //
  // All cast functions use **deferred execution**: the cast request is
  // queued and executed on the game's main thread (PeekMessage hook)
  // on the next tick. The function returns immediately with result
  // code 12 ("Queued").
  //
  // Use game.last_cast_result() on the following frame to retrieve the
  // actual outcome (0 = success, etc.).
  //
  // Result codes:
  //    0 = success
  //    1 = no module base
  //    2 = spell book manager not found
  //    3 = spell not in spell book
  //    4 = could not read target GUID
  //    5 = SEH fault (function disabled)
  //    6 = invalid target GUID (zero/sentinel)
  //    7 = target GUID not found in object manager
  //    8 = invalid spell ID (zero)
  //    9 = throttled (previous cast still pending in queue)
  //   10 = not ready (game returned false from CastSpellBridge)
  //   11 = on cooldown / GCD active (pre-check)
  //   12 = queued for main thread (check last_cast_result next frame)

  /** Cast options table for cast_spell / cast_spell_at. */
  interface CastOpts {
    /** If true, cast from pet spell book (default false). */
    pet?: boolean;
    /**
     * Ground targeting mode (default 0):
     *   0 = normal unit target (via GUID)
     *   1 = AoE at target entity's feet (ground_at_entity)
     *   2 = AoE at cursor/world position (ground_at_cursor)
     *
     * Mode 1 is the most useful for programmatic AoE — places the spell
     * at the targeted unit's location without requiring cursor interaction.
     * Mode 2 requires the 3D cursor position to be valid (terrain raycast).
     */
    ground?: number;
    /** If true, bypass the cooldown/GCD pre-check (default false). */
    skip_cd?: boolean;
  }

  /**
   * Cast a spell by ID or name using the player's current target.
   * The cast is queued for execution on the game's main thread.
   *
   * @param spell_id_or_name - Numeric spell ID or string spell name (case-insensitive).
   * @param opts - Optional: CastOpts table or boolean (legacy is_pet).
   * @returns [result_code, description] — typically [12, "queued for main thread"].
   *
   * @example
   * game.cast_spell(1543, { ground = 1 })
   * -- next frame:
   * local code, desc = game.last_cast_result()
   */
  function cast_spell(spell_id_or_name: number | string, opts?: CastOpts | boolean): LuaMultiReturn<[number, string]>;

  /**
   * Cast a spell at a specific target by GUID.
   * @param spell_id - Numeric spell ID.
   * @param guid_lo - Lower 64 bits of the target GUID.
   * @param guid_hi - Upper 64 bits of the target GUID.
   * @param opts - Optional: CastOpts table or boolean (legacy is_pet).
   * @returns [result_code, description].
   */
  function cast_spell_at(spell_id: number, guid_lo: number, guid_hi: number, opts?: CastOpts | boolean): LuaMultiReturn<[number, string]>;

  /**
   * Cast a spell at a specific target by obj_ptr.
   * Resolves the 128-bit GUID from the OM snapshot in C++, avoiding Lua
   * double-precision truncation of 64-bit GUID halves.
   * Preferred over cast_spell_at for all entity-targeted casts.
   * @param spell_id - Numeric spell ID.
   * @param obj_ptr - Entity object pointer (from entity.obj_ptr).
   * @param opts - Optional: CastOpts table or boolean (legacy is_pet).
   * @returns [result_code, description].
   */
  function cast_spell_at_unit(spell_id: number, obj_ptr: number, opts?: CastOpts | boolean): LuaMultiReturn<[number, string]>;

  /** Options for cast_direct / cast_direct_at (no pet — bypasses spell book). */
  interface DirectCastOpts {
    /**
     * Ground targeting mode (default 0):
     *   0 = normal unit target (via GUID)
     *   1 = AoE at target entity's feet (ground_at_entity)
     *   2 = AoE at cursor/world position (ground_at_cursor)
     */
    ground?: number;
    /** If true, bypass the cooldown/GCD pre-check (default false). */
    skip_cd?: boolean;
  }

  /**
   * Cast any spell by ID directly via CastSpellBridge, bypassing spell book
   * slot resolution. Works for spells not in the player's spell book.
   * Uses the player's current target.
   * @param spell_id - Numeric spell ID.
   * @param opts - Optional: DirectCastOpts table.
   * @returns [result_code, description].
   */
  function cast_direct(spell_id: number, opts?: DirectCastOpts): LuaMultiReturn<[number, string]>;

  /**
   * Cast any spell by ID directly at a specific target GUID, bypassing
   * spell book slot resolution.
   * @param spell_id - Numeric spell ID.
   * @param guid_lo - Lower 64 bits of the target GUID.
   * @param guid_hi - Upper 64 bits of the target GUID.
   * @param opts - Optional: DirectCastOpts table.
   * @returns [result_code, description].
   */
  function cast_direct_at(spell_id: number, guid_lo: number, guid_hi: number, opts?: DirectCastOpts): LuaMultiReturn<[number, string]>;

  /** Options for cast_at_pos. */
  interface CastAtPosOpts {
    /** Cast from pet spell book (default false). */
    pet?: boolean;
    /** Use direct CastSpellBridge path, bypassing spell book (default false). */
    direct?: boolean;
    /** If true, bypass the cooldown/GCD pre-check (default false). */
    skip_cd?: boolean;
  }

  /**
   * Cast a ground-targeted spell at a specific world position (Vec3).
   * Temporarily hooks the cursor raycast to inject the position, then
   * casts with ground_at_cursor=1 through the normal game path.
   *
   * Useful for AoE spells that need a specific location. The position
   * can come from any source (player pos, target pos, arbitrary coords).
   *
   * @param spell_id - Numeric spell ID.
   * @param x - World X coordinate.
   * @param y - World Y coordinate.
   * @param z - World Z coordinate.
   * @param opts - Optional: { pet=bool, direct=bool, skip_cd=bool }.
   * @returns [result_code, description].
   */
  function cast_at_pos(spell_id: number, x: number, y: number, z: number, opts?: CastAtPosOpts): LuaMultiReturn<[number, string]>;

  /**
   * Get the result of the most recent deferred cast processed on the main
   * thread. Call this on the frame after a cast function returns code 12
   * ("queued for main thread") to retrieve the actual outcome.
   *
   * @returns [result_code, description] where 0 = success.
   *
   * @example
   * local code = game.cast_spell(1543)
   * -- code == 12 ("queued")
   * -- next frame:
   * local real_code, real_desc = game.last_cast_result()
   * -- real_code == 0 ("success") or 11 ("on cooldown"), etc.
   */
  function last_cast_result(): LuaMultiReturn<[number, string]>;

  /**
   * Stop the current cast. If spell_id is given, only stops that spell.
   * @param spell_id - Optional spell ID to stop (default 0 = stop any).
   */
  function stop_casting(spell_id?: number): void;

  /**
   * Find a spell ID by name (case-insensitive search through spell book).
   * Searches both player and pet spell books.
   * @param name - Spell name to search for.
   * @returns Spell ID, or nil if not found.
   */
  function find_spell_id(name: string): number | null;

  // ---- Spell Info Queries ----

  /**
   * Get the localized name of a spell by ID.
   * Uses the spell DB record at offset +0x00.
   *
   * @param spell_id - Numeric spell identifier.
   * @returns Spell name string, or nil if the spell doesn't exist.
   */
  function get_spell_name(spell_id: number): string | null;

  /** Spell info returned by game.get_spell_info(). */
  interface SpellInfoResult {
    /** Localized spell name. */
    name: string;
    /** The spell ID that was queried. */
    spell_id: number;
    /** Cast time in milliseconds (0 = instant). */
    cast_time: number;
    /** Minimum range in yards (float). */
    min_range: number;
    /** Maximum range in yards (float, 0 = melee/self). */
    max_range: number;
    /** Spell description text (raw, may contain $-placeholders), or nil. */
    description: string | null;
    /** Aura/buff description text, or nil. */
    aura_description: string | null;
    /** Fully resolved description with computed values (e.g. "heals for 1234"), or nil. */
    formatted_description: string | null;
    /** Fully resolved aura description with computed values, or nil. */
    formatted_aura_description: string | null;
  }

  /**
   * Get spell info as a table.
   *
   * @param spell_id - Numeric spell identifier.
   * @returns SpellInfoResult table, or nil if the spell doesn't exist.
   */
  function get_spell_info(spell_id: number): SpellInfoResult | null;

  /** Raw spell record dump returned by game.dump_spell_record(). */
  interface SpellRecordDump {
    /** Absolute memory address of the record. */
    address: number;
    /** Number of bytes dumped. */
    size: number;
    /** Hex dump string with offset annotations and ASCII. */
    hex: string;
    /** Array of int32 values at each 4-byte boundary (1-indexed). */
    int32s: number[];
  }

  /**
   * Dump raw bytes from a spell DB record for reverse engineering.
   * Useful for discovering field offsets (description, cast time, range, etc.).
   *
   * The name string is at +0x00 (relative offset, verified working).
   * Other field offsets need IDA analysis.
   *
   * @param spell_id - Numeric spell identifier.
   * @param num_bytes - Number of bytes to dump (default 128, max 512).
   * @returns SpellRecordDump table, or nil if spell not found.
   */
  function dump_spell_record(spell_id: number, num_bytes?: number): SpellRecordDump | null;

  // ---- Cooldown & Charge Queries ----

  /** Cooldown info returned by game.spell_cooldown(). */
  interface SpellCooldownInfo {
    /** Game time when cooldown started (seconds). */
    start: number;
    /** Total cooldown length (seconds). */
    duration: number;
    /** False if the spell is permanently disabled. */
    enabled: boolean;
    /** Haste modifier (1.0 = normal). */
    mod_rate: number;
    /** Shared cooldown category ID. */
    category: number;
    /** True if the spell is currently on cooldown. */
    on_cooldown: boolean;
    /** Seconds remaining until ready (0 if off CD). */
    remaining: number;
  }

  /**
   * Get the current cooldown state for a spell.
   * Reads directly from the game's cooldown manager.
   * @param spell_id - Numeric spell ID.
   * @returns Cooldown info table, or nil if unavailable.
   */
  function spell_cooldown(spell_id: number): SpellCooldownInfo | null;

  /** Charge info returned by game.spell_charges(). */
  interface SpellChargeInfo {
    /** Charges available right now. */
    current: number;
    /** Maximum charges (0 = spell has no charge system). */
    max: number;
    /** When the current charge began recharging (seconds). */
    cooldown_start: number;
    /** Recharge time per charge (seconds). */
    cooldown_duration: number;
    /** Haste modifier. */
    mod_rate: number;
    /** Seconds until next charge is ready (0 if fully charged). */
    time_to_next: number;
  }

  /**
   * Get the current charge state for a spell.
   * For spells without charges, max will be 0.
   * @param spell_id - Numeric spell ID.
   * @returns Charge info table, or nil if unavailable.
   */
  function spell_charges(spell_id: number): SpellChargeInfo | null;

  // ---- Unit Casting / Channeling Info ----

  /** Cast/channel info returned by game.unit_casting_info / game.unit_channel_info. */
  interface UnitSpellStateInfo {
    /** The spell ID being cast or channeled. */
    spell_id: number;
    /** Spell name (resolved from spell DB). May be absent for unknown spells. */
    spell_name?: string;
    /** Game clock timestamp when the cast/channel started (seconds). */
    start_time: number;
    /** Game clock timestamp when the cast/channel will finish (seconds). */
    end_time: number;
    /** Seconds remaining until the cast/channel completes. */
    remaining: number;
    /** True if the cast/channel cannot be interrupted. */
    not_interruptible: boolean;
  }

  /**
   * Query the current CASTING state of a unit via the game's internal spell
   * state resolver. Uses the clean function chain traced from UnitCastingInfo.
   *
   * Accepts standard WoW unit tokens: "player", "target", "focus",
   * "party1"..."party4", "boss1"..."boss4", etc.
   *
   * @param unit_token - WoW unit token string.
   * @returns Cast info table if the unit is currently casting, nil otherwise.
   *
   * @example
   * local cast = game.unit_casting_info("target")
   * if cast then
   *   print(cast.spell_name, cast.remaining .. "s left")
   *   if not cast.not_interruptible then
   *     -- safe to kick at the right time
   *   end
   * end
   */
  function unit_casting_info(unit_token: string): UnitSpellStateInfo | null;

  /**
   * Query the current CHANNELING state of a unit. Same interface as
   * unit_casting_info but reads the channel slot of the spell state object.
   *
   * @param unit_token - WoW unit token string.
   * @returns Channel info table if the unit is channeling, nil otherwise.
   *
   * @example
   * local chan = game.unit_channel_info("target")
   * if chan and not chan.not_interruptible and chan.remaining > 0.5 then
   *   game.cast_spell("Kick")  -- interrupt the channel
   * end
   */
  function unit_channel_info(unit_token: string): UnitSpellStateInfo | null;

  // ---- IsCurrentSpell / IsSpellInRange ----

  /**
   * Check if a spell is currently being cast or channeled by the player.
   * Mirrors WoW API `IsCurrentSpell(spellID)`.
   *
   * @param spell_id - Numeric spell identifier.
   * @returns true if the spell is the current cast or channel, false otherwise.
   *
   * @example
   * if game.is_current_spell(116) then
   *   -- Frostbolt is currently being cast
   * end
   */
  function is_current_spell(spell_id: number): boolean;

  /**
   * Check if a spell is in range of a target entity.
   * Mirrors WoW API `IsSpellInRange(spellName, unit)` return convention.
   *
   * Calls the game's internal range-check function (sub_26A2F00), which
   * resolves spell effects, target entity, and performs the actual distance
   * calculation — identical to the Lua API behavior.
   *
   * @param spell_id - Numeric spell identifier.
   * @param target_obj_ptr - Target entity's obj_ptr (from ObjectManager).
   * @returns 1 if in range, 0 if out of range, nil if spell has no range
   *          component or the target is invalid.
   *
   * @example
   * local t = game.target()
   * if t then
   *   local inRange = game.is_spell_in_range(116, t.obj_ptr)
   *   if inRange == 1 then
   *     -- Frostbolt is in range of our target
   *   elseif inRange == 0 then
   *     -- Out of range
   *   else
   *     -- nil: spell has no range check (e.g. self-buff)
   *   end
   * end
   */
  function is_spell_in_range(spell_id: number, target_obj_ptr: number): number | null;

  /**
   * Check if a spell is usable by the player right now.
   * Mirrors WoW API `IsUsableSpell(spellID)`.
   *
   * Checks general usability (cooldown, stance, form, target requirements)
   * and power sufficiency (mana, energy, rage, etc.) via the game's internal
   * functions.
   *
   * @param spell_id - Numeric spell identifier.
   * @returns Two booleans `(usable, nomana)`:
   *   - `usable` = true if the spell can be cast
   *   - `nomana` = true if the only blocker is insufficient power
   *   Returns `(nil, nil)` if the function is unavailable.
   *
   * @example
   * local usable, nomana = game.is_usable_spell(116)
   * if usable then
   *   -- Frostbolt is castable
   * elseif nomana then
   *   -- Would be castable but not enough mana
   * end
   */
  function is_usable_spell(spell_id: number): LuaMultiReturn<[boolean | null, boolean | null]>;

  // ---- Utility ----

  /**
   * Compute 3D Euclidean distance between two points.
   * Use entity.position to get coordinates for entities.
   *
   * @example
   * local p = game.local_player().position
   * local t = game.target()  -- get target entity from objects
   * -- find target entity position:
   * for _, e in ipairs(game.objects()) do
   *   if e.guid == t.guid and e.position then
   *     local d = game.distance(p.x, p.y, p.z, e.position.x, e.position.y, e.position.z)
   *   end
   * end
   */
  function distance(x1: number, y1: number, z1: number,
                    x2: number, y2: number, z2: number): number;

  /**
   * Angle from point 1 to point 2 in radians (0..2π).
   *
   * @example
   *     local a = game.angle_to(me.x, me.y, target.x, target.y)
   */
  function angle_to(x1: number, y1: number, x2: number, y2: number): number;

  /**
   * Returns true if the source entity/point is facing the target within
   * `threshold` radians (default π/2 = ±90° = 180° frontal cone).
   *
   * **Entity form** — reads position and facing from obj_ptrs:
   *
   *     game.is_facing(source_ptr, target_ptr)
   *     game.is_facing(source_ptr, target_ptr, math.pi / 2)  -- 90° cone
   *
   * **Coordinate form** — explicit facing and XY:
   *
   *     game.is_facing(facing, x1, y1, x2, y2)
   *     game.is_facing(facing, x1, y1, x2, y2, math.pi / 2)
   */
  function is_facing(source_ptr: number, target_ptr: number, threshold?: number): boolean;
  function is_facing(facing: number, x1: number, y1: number,
                     x2: number, y2: number, threshold?: number): boolean;

  /**
   * Cast a ray through the world and return hit information, or nil if no hit.
   *
   * @param flags  Intersection phases bitmask (default 0x7F = all).
   *               Bit 0-1: terrain/liquid, Bit 2-6: M2/model.
   * @returns `{ hit_x, hit_y, hit_z, distance, hit_type }` or `nil`.
   *          hit_type: 1=terrain, 2=model, 3=WMO/doodad.
   *
   * @example
   *     local hit = game.traceline(me.x, me.y, me.z, t.x, t.y, t.z)
   *     if hit then print("blocked at", hit.hit_x, hit.hit_y, hit.hit_z) end
   */
  function traceline(x1: number, y1: number, z1: number,
                     x2: number, y2: number, z2: number,
                     flags?: number): { hit_x: number; hit_y: number; hit_z: number; distance: number; hit_type: number } | null;

  /**
   * Returns true if there is clear line-of-sight between two 3D points
   * (no world geometry blocks the path).
   *
   * @param flags  Same as traceline (default 0x7F = all).
   *
   * @example
   *     if game.los(me.x, me.y, me.z, t.x, t.y, t.z) then
   *       -- target is visible, ok to cast
   *     end
   */
  function los(x1: number, y1: number, z1: number,
               x2: number, y2: number, z2: number,
               flags?: number): boolean;

  /**
   * Returns true if no world geometry blocks the ray between two entities.
   * Pure geometry check with no facing requirement.
   *
   * @param flags  Intersection bitmask (default 0x7F = all).
   *
   * @example
   *     if game.is_visible(player_ptr, target_ptr) then ...
   */
  function is_visible(source_ptr: number, target_ptr: number, flags?: number): boolean;

  /**
   * Returns true if the source is facing the target (180° frontal arc)
   * AND no world geometry blocks the ray between them.
   *
   * @param flags  Intersection bitmask (default 0x7F = all).
   *
   * @example
   *     if game.in_los(player_ptr, target_ptr) then
   *       -- facing target and nothing in the way
   *     end
   */
  function in_los(source_ptr: number, target_ptr: number, flags?: number): boolean;

  // =========================================================================
  // Unit Predicates — on-demand queries for combat routine conditions
  // =========================================================================

  /**
   * Returns true if the unit currently has an aura matching the given
   * spell ID or spell name.
   */
  function has_aura(obj_ptr: number, spell_id_or_name: number | string): boolean;

  /**
   * Returns detailed info about the first matching aura, or nil.
   *
   * duration = total duration in seconds (0 = permanent).
   * expire_time = absolute game-time seconds when aura expires.
   * remaining = expire_time - now in seconds (computed, 0 for permanent buffs).
   */
  function aura_info(obj_ptr: number, spell_id_or_name: number | string): {
    spell_id: number;
    name?: string;
    stacks: number;
    duration: number;
    remaining: number;
    expire_time: number;
    flags: number;
    is_helpful: boolean;
    is_harmful: boolean;
    is_from_player: boolean;
    caster_type: number;
    time_mod: number;
    instance_id: number;
    caster_lo: number;
    caster_hi: number;
    caster_name?: string;
  } | null;

  /**
   * Returns full aura data for a specific aura slot index.
   */
  function scan_aura_entry(obj_ptr: number, aura_index: number): {
    entry_ptr: number;
    spell_id: number;
    name?: string;
    stacks: number;
    flags: number;
    duration: number;
    remaining: number;
    expire_time: number;
    is_helpful: boolean;
    is_harmful: boolean;
    is_from_player: boolean;
    caster_type: number;
    time_mod: number;
    instance_id: number;
    caster_lo: number;
    caster_hi: number;
    caster_name?: string;
  } | null;

  /**
   * Returns the unit's health as a percentage (0–100), or nil if
   * health cannot be resolved.
   */
  function unit_health_pct(obj_ptr: number): number | null;

  /**
   * Returns the unit's current power, max power, and power percentage.
   * If power_type is omitted, returns the unit's default power.
   *
   * Power types: 0=Mana, 1=Rage, 2=Focus, 3=Energy, 6=RunicPower,
   *              7=SoulShards, 8=Eclipse, 9=HolyPower, etc.
   */
  function unit_power(obj_ptr: number, power_type?: number): LuaMultiReturn<[number, number, number]>;

  /** Returns the raw UNIT_FIELD_FLAGS bitmask. */
  function unit_flags(obj_ptr: number): number;

  /** Returns true if the unit has the IN_COMBAT flag set. */
  function unit_in_combat(obj_ptr: number): boolean;

  /** Returns true if the unit's health is <= 0. */
  function unit_is_dead(obj_ptr: number): boolean;

  /** Returns true if the unit is dead OR a ghost (running back from GY). */
  function unit_dead_or_ghost(obj_ptr: number): boolean;

  /**
   * Returns true if the first unit can attack the second, using the game's
   * internal UnitCanAttack logic (pattern-scanned at runtime).
   * With one arg, checks if the local player can attack the unit.
   */
  function unit_can_attack(obj_ptr: number): boolean;
  function unit_can_attack(obj_ptr_a: number, obj_ptr_b: number): boolean;

  /**
   * Convenience: checks if the local player can attack the given unit.
   * Equivalent to unit_can_attack(obj_ptr) — always from player's POV.
   */
  function unit_is_attackable(obj_ptr: number): boolean;

  /**
   * Returns the creature type name and numeric ID.
   * Names: "Beast", "Dragonkin", "Demon", "Elemental", "Giant", "Undead",
   *        "Humanoid", "Critter", "Mechanical", "Totem", etc.
   * Returns nil if the entity has no CGUnit.
   */
  function unit_creature_type(obj_ptr: number): LuaMultiReturn<[string, number]> | null;

  /**
   * Returns the WoW-standard reaction value (1-8):
   *   1=Hated, 2=Hostile, 3=Unfriendly, 4=Neutral,
   *   5=Friendly, 6=Honored, 7=Revered, 8=Exalted
   * With one arg, checks local player → unit. With two, checks a → b.
   * Returns nil on failure.
   */
  function unit_reaction(obj_ptr: number): number | null;
  function unit_reaction(obj_ptr_a: number, obj_ptr_b: number): number | null;

  /**
   * Returns true if the units are enemies (reaction 1-2: Hated/Hostile).
   * With one arg, checks local player → unit.
   */
  function unit_is_enemy(obj_ptr: number): boolean;
  function unit_is_enemy(obj_ptr_a: number, obj_ptr_b: number): boolean;

  /**
   * Returns true if the units are friends (reaction 5-8: Friendly+).
   * With one arg, checks local player → unit.
   */
  function unit_is_friend(obj_ptr: number): boolean;
  function unit_is_friend(obj_ptr_a: number, obj_ptr_b: number): boolean;

  /**
   * Returns the group role for a unit: "TANK", "HEALER", "DAMAGER", or "NONE".
   * Also returns the numeric role ID (0=TANK, 1=HEALER, 2=DAMAGER, -1=NONE).
   * Returns nil if the entity cannot be resolved.
   */
  function unit_role(obj_ptr: number): LuaMultiReturn<[string, number]> | null;

  /** Returns true if the unit's assigned group role is TANK. */
  function unit_is_tank(obj_ptr: number): boolean;

  /** Returns true if the unit's assigned group role is HEALER. */
  function unit_is_healer(obj_ptr: number): boolean;

  /** Returns true if the unit's assigned group role is DPS/DAMAGER. */
  function unit_is_dps(obj_ptr: number): boolean;

  /**
   * Query a unit's threat on a mob (UnitDetailedThreatSituation).
   * With one arg (mob_obj_ptr), queries the local player's threat.
   * Returns nil if the mob has no threat table or the unit is not on it.
   *
   * @returns isTanking, status (0-3), scaledPercentage, rawPercentage, threatValue
   */
  function unit_threat(mob_obj_ptr: number):
    LuaMultiReturn<[boolean, number, number, number, number]> | null;
  function unit_threat(unit_obj_ptr: number, mob_obj_ptr: number):
    LuaMultiReturn<[boolean, number, number, number, number]> | null;

  /** A single entry from a mob's internal threat hash map. */
  interface ThreatEntry {
    guid_lo: number;
    guid_hi: number;
    status: number;
    raw_pct: number;
    threat_val: number;
    is_tanking: boolean;
  }

  /**
   * Returns the full threat table for a mob by walking its internal hash map.
   * Each entry contains the GUID of a unit on the threat table, its status,
   * raw threat percentage, raw threat value, and whether it is tanking.
   * Returns an empty table if the mob has no threat table.
   */
  function unit_threat_list(mob_obj_ptr: number): ThreatEntry[];

  /** Returns true if the player is in any group (party or raid). */
  function is_in_group(): boolean;

  /** Returns true if the player is in a raid group. */
  function is_in_raid(): boolean;

  /** Returns the number of group members (0 if not in a group). */
  function group_size(): number;

  /** Returns true if the current group (party or raid) is full. */
  function is_party_full(): boolean;

  /** Returns true if the unit is in the player's party/group roster. */
  function unit_in_party(obj_ptr: number): boolean;

  /** Returns true if in a raid AND the unit is on the roster. */
  function unit_in_raid(obj_ptr: number): boolean;

  /** A group/raid member entry from the roster member pointer array. */
  interface GroupMember {
    guid_lo: number;
    guid_hi: number;
    /** 1-based roster index */
    index: number;
    /** 1-based raid subgroup */
    subgroup: number;
    /** 0 = member, 1 = assistant, 2 = leader */
    rank: number;
    /** "MAINTANK", "MAINASSIST", or "" */
    role: string;
    /** Class ID from member struct (1=Warrior..11=Druid), always available */
    class_id?: number;
    /** Localized class name e.g. "Priest" */
    class?: string;
    /** Uppercase English class token e.g. "PRIEST" */
    fileName?: string;
    /** Combat role decoded from LFG bitmask: "TANK", "HEALER", "DAMAGER", or "NONE" */
    combatRole: string;
    /** true if entity is visible in the ObjectManager */
    online: boolean;
    obj_ptr?: number;
    name?: string;
    level?: number;
  }

  /**
   * Returns all members from the roster (up to 40 for raids).
   * Each entry includes rank, subgroup, role, and entity data if online.
   */
  function group_members(): GroupMember[];

  /**
   * Returns the number of group members.
   * @param category 0 = home (party), 1 = instance (raid). Defaults to active group.
   */
  function num_group_members(category?: number): number;

  /** Detailed roster info for a single raid/party member. */
  interface RaidRosterInfo {
    guid_lo: number;
    guid_hi: number;
    index: number;
    subgroup: number;
    rank: number;
    role: string;
    isML: boolean;
    online: boolean;
    isDead: boolean;
    /** "TANK", "HEALER", "DAMAGER", or "NONE" */
    combatRole: string;
    obj_ptr?: number;
    name?: string;
    level?: number;
    class_id?: number;
    /** Localized class name e.g. "Priest" */
    class?: string;
    /** Uppercase English class token e.g. "PRIEST" */
    fileName?: string;
  }

  /**
   * Returns detailed roster info for a raid/party member at a given index.
   * @param index 1-based roster index (1..40)
   * @returns Table of member data, or nil if the slot is empty.
   */
  function raid_roster_info(index: number): RaidRosterInfo | null;

  /**
   * Returns the current game clock in seconds.
   * Uses the game's internal GetGameTime (ms) divided by 1000.
   */
  function game_time(): number;

  /**
   * Absolute path to the scripts directory (set by C++ at init).
   * Use this to build paths for plugin-local files (e.g. settings).
   */
  const SCRIPTS_DIR: string;

  // ---- Player Facing ----

  /**
   * Set the player's facing direction. Both arguments are in **entity
   * convention** (standard math: 0 = East, π/2 = North, π = West, -π/2 = South).
   *
   * The function is deferred to the game's main thread via the PeekMessage
   * hook. It uses the MoveAndSteer mechanism internally: writes a rotation
   * delta to CMovement+0x13C, starts MoveAndSteer (flag 3), then immediately
   * runs the MoveAndSteerStop sequence to commit the facing and send the
   * server packet.
   *
   * @param desired - The angle the character should face (entity convention, radians).
   * @param current - The character's current facing angle, from game.entity_facing().
   * @returns [ok, message] — ok is true if the request was queued.
   *
   * @example
   * // Face North
   * local cur = game.entity_facing(game.local_player().obj_ptr)
   * game.set_facing(math.pi / 2, cur)
   *
   * @example
   * // Face target
   * local p = game.local_player().position
   * local tx, ty = game.target_position()
   * local desired = game.angle_to(p.x, p.y, tx, ty)
   * local cur = game.entity_facing(game.local_player().obj_ptr)
   * game.set_facing(desired, cur)
   */
  function set_facing(desired: number, current: number): LuaMultiReturn<[boolean, string]>;

  /**
   * Get the current target's world position.
   * Reads the target GUID, resolves via ObjectManager, returns position.
   * @returns x, y, z or nil if no target / position unavailable.
   */
  function target_position(): LuaMultiReturn<[number, number, number]> | null;

  // ---- Turn Actions & Bindings ----

  /**
   * Queue a keyboard turn action.
   * @param action - One of: "left_start", "left_stop", "right_start", "right_stop".
   * @returns true if queued, false if busy.
   */
  function turn(action: string): boolean;

  /**
   * Dispatch any keybinding by name through the game's RunBinding pipeline.
   * @param name - Binding name (e.g. "MOVEFORWARD", "TOGGLEAUTORUN").
   * @param is_down - true = key down (start), false = key up (stop). Default true.
   * @returns true if queued.
   */
  function run_binding(name: string, is_down?: boolean): boolean;

  /** ECS Tag ID constants. */
  const TAG: {
    Unit: number;
    Player: number;
    ActivePlayer: number;
    GameObject: number;
    Item: number;
    Container: number;
    DynObj: number;
    Corpse: number;
    AreaTrigger: number;
    ActiveObj: number;
    VisibleObj: number;
    LootObject: number;
    FEntityPos: number;
    FEntityLocalMat: number;
    FEntityWorldMat: number;
  };
}

// ---------------------------------------------------------------------------
// Plugin Interface
// ---------------------------------------------------------------------------

/**
 * Lua plugins must return a table with the following shape.
 * Place your plugin in scripts/<name>/plugin.lua or
 * scripts/CommunityScripts/<name>/plugin.lua.
 */
interface JmrMoPPlugin {
  /** Required. Display name of the plugin. */
  name: string;

  /** Optional. Short description shown in the Plugin Browser. */
  description?: string;

  /** Optional. Author name. */
  author?: string;

  /** Called when the plugin is enabled. */
  onEnable?(): void;

  /** Called when the plugin is disabled. */
  onDisable?(): void;

  /** Called every frame before drawing. Use for logic/polling. */
  onTick?(): void;

  /** Called every frame during the ImGui render pass. Draw UI here. */
  onDraw?(): void;
}

// ---------------------------------------------------------------------------
// Utility types (Lua multi-return emulation)
// ---------------------------------------------------------------------------

type LuaMultiReturn<T extends any[]> = T;
