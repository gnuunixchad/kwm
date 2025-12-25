const BorderColor = struct {
    focus: u32,
    unfocus: u32,
    urgent: u32,
};

pub const gap: u32 = 3;
pub const border_width: u32 = 3;
pub const border_color: BorderColor = .{
    .focus = 0xA54242,
    .unfocus = 0x707880,
    .urgent = 0xff0000,
};
