const std = @import("std");

pub const ThreadPool = struct {
    const ThreadChannel = struct { thread: std.Thread };
    const ShutdownPolicyEnum = enum { Continue, IfTasksFinished, IgnoreRemainingTasks };
    allocator: std.mem.Allocator,
    thread_channels: std.ArrayList(ThreadChannel),
    tasks: TaskQueue = TaskQueue{},
    task_mtx: std.Thread.Mutex = std.Thread.Mutex{},
    shutdown_policy: ShutdownPolicyEnum = .Continue,

    pub fn init(allocator: std.mem.Allocator) ThreadPool {
        return ThreadPool{
            .allocator = allocator,
            .thread_channels = std.ArrayList(ThreadChannel).init(allocator),
        };
    }

    const StartThreadsConfig = struct { num_threads: ?usize = null }; 
    pub fn startThreads(self: *ThreadPool, config: StartThreadsConfig) !void {
        try self.thread_channels.resize(config.num_threads orelse try std.Thread.getCpuCount() - 1);
        for (self.thread_channels.items) |*thread_channel| {
            thread_channel.thread = try std.Thread.spawn(.{}, threadLoopFn, .{self});
        }
    }
    
    const TaskCompleteEnum = enum { FinishAllTasks, FinishCurrentTask };
    const ThreadPoolDeinitConfig = struct { finish_policy: TaskCompleteEnum = .FinishAllTasks };
    pub fn deinit(self: *ThreadPool, config: ThreadPoolDeinitConfig) void {
        self.shutdown_policy = switch(config.finish_policy) {
            .FinishAllTasks => .IfTasksFinished,
            .FinishCurrentTask => .IgnoreRemainingTasks,
        };

        for (self.thread_channels.items) |*thread_channel| {
            thread_channel.thread.join();
        }

        self.thread_channels.clearAndFree();
    }

    pub fn scheduleTask(self: *ThreadPool, task: *Task) void {
        task.semaphore_ptr.incrementWaitCount();
        self.task_mtx.lock();
        self.tasks.append(task);
        self.task_mtx.unlock();
    }

    fn TypeOfChild(comptime T: type) type {
        switch (@typeInfo(T)) {
            .Pointer => |ptr_info| {
                return ptr_info.child;
            },
            .Array => |arr_info| return arr_info.child,
            else => @compileError("type is not pointer or array"),
        }

        //return @typeInfo(info.child).Pointer.child;
    }

    fn scheduleMultitask(self: *ThreadPool, allocator: std.mem.Allocator, semaphore: *TaskSemaphore, slice: anytype, func: *const fn(*Task) void) 
    ![]GContext([]TypeOfChild(@TypeOf(slice))) {
        comptime switch (@typeInfo(@TypeOf(slice))) {
            .Pointer => {},
            else => @compileError("argument 'slice' is not of type slice"),
        };

        if (slice.len < 1) {
            return &.{};
        }

        const default_task_len = if (slice.len / self.thread_channels.items.len == 0) 1 else slice.len / self.thread_channels.items.len; 
        const num_tasks = 
            if (slice.len >= self.thread_channels.items.len) 
                self.thread_channels.items.len
            else
                slice.len; 

        const contexts = try allocator.alloc(GContext([]TypeOfChild(@TypeOf(slice))), num_tasks);

        for (contexts, 0..) |*context, i| {
            const end_val: usize = if (i == num_tasks - 1) slice.len else (i + 1) * default_task_len;
            context.value = slice[i * default_task_len..end_val];
            context.task = Task.init(func, semaphore);
            self.scheduleTask(&context.task);
        }

        return contexts;
    }

    pub inline fn forEach(self: *ThreadPool, slice: anytype, func: *const fn(*Task) void) !void {
        var semaphore = TaskSemaphore{};
        const ctxts = try self.scheduleMultitask(self.allocator, &semaphore, slice, func);
        semaphore.wait();
        self.allocator.free(ctxts);
    }

    pub inline fn forEachNonBlocking(self: *ThreadPool, allocator: std.mem.Allocator, semaphore: *TaskSemaphore, slice: anytype, func: *const fn(*Task) void) ![]GContext([]TypeOfChild(@TypeOf(slice))) {
        return try self.scheduleMultitask(allocator, semaphore, slice, func);
    }

    fn threadLoopFn(tp: *ThreadPool) void {
        const thread_ID: u32 = std.Thread.getCurrentId();
        _ = thread_ID;

        while (true) {
            switch (tp.shutdown_policy) {
                .Continue => {},
                .IfTasksFinished => {
                    tp.task_mtx.lock();
                    const num_tasks = tp.tasks.len;
                    tp.task_mtx.unlock();
                    if (num_tasks == 0) {
                        break;
                    }
                },
                .IgnoreRemainingTasks => break,
            }

            tp.task_mtx.lock();
            const task_opt = tp.tasks.popFirst();
            tp.task_mtx.unlock();

            if (task_opt) |task| {
                task.run();
            }
        }
    }
};

const TaskQueue = struct {
    const Self = @This();

    /// Node inside the linked list wrapping the actual data.
    const Node = Task;

    first: ?*Node = null,
    last: ?*Node = null,
    len: usize = 0,

    fn insertAfter(list: *Self, node: *Node, new_node: *Node) void {
        new_node.prev = node;
        if (node.next) |next_node| {
            // Intermediate node.
            new_node.next = next_node;
            next_node.prev = new_node;
        } else {
            // Last element of the list.
            new_node.next = null;
            list.last = new_node;
        }
        node.next = new_node;

        list.len += 1;
    }

    fn insertBefore(list: *Self, node: *Node, new_node: *Node) void {
        new_node.next = node;
        if (node.prev) |prev_node| {
            // Intermediate node.
            new_node.prev = prev_node;
            prev_node.next = new_node;
        } else {
            // First element of the list.
            new_node.prev = null;
            list.first = new_node;
        }
        node.prev = new_node;

        list.len += 1;
    }

    fn concatByMoving(list1: *Self, list2: *Self) void {
        const l2_first = list2.first orelse return;
        if (list1.last) |l1_last| {
            l1_last.next = list2.first;
            l2_first.prev = list1.last;
            list1.len += list2.len;
        } else {
            // list1 was empty
            list1.first = list2.first;
            list1.len = list2.len;
        }
        list1.last = list2.last;
        list2.first = null;
        list2.last = null;
        list2.len = 0;
    }

    fn append(list: *Self, new_node: *Node) void {
        if (list.last) |last| {
            // Insert after last.
            list.insertAfter(last, new_node);
        } else {
            // Empty list.
            list.prepend(new_node);
        }
    }

    fn prepend(list: *Self, new_node: *Node) void {
        if (list.first) |first| {
            // Insert before first.
            list.insertBefore(first, new_node);
        } else {
            // Empty list.
            list.first = new_node;
            list.last = new_node;
            new_node.prev = null;
            new_node.next = null;

            list.len = 1;
        }
    }

    fn remove(list: *Self, node: *Node) void {
        if (node.prev) |prev_node| {
            // Intermediate node.
            prev_node.next = node.next;
        } else {
            // First element of the list.
            list.first = node.next;
        }

        if (node.next) |next_node| {
            // Intermediate node.
            next_node.prev = node.prev;
        } else {
            // Last element of the list.
            list.last = node.prev;
        }

        list.len -= 1;
    }

    fn pop(list: *Self) ?*Node {
        const last = list.last orelse return null;
        list.remove(last);
        return last;
    }

    fn popFirst(list: *Self) ?*Node {
        const first = list.first orelse return null;
        list.remove(first);
        return first;
    }
};

pub const TaskSemaphore = struct {
    /// num_complete is incremented every time a task with this semaphore is completed
    num_complete: usize = 0,
    /// wait_count is incremented every time a task with this semaphore is scheduled
    wait_count: usize = 0,
    mtx: std.Thread.Mutex = std.Thread.Mutex{},

    fn incrementWaitCount(self: *TaskSemaphore) void {
        self.mtx.lock();
        self.wait_count += 1;
        self.mtx.unlock();
    }

    fn incrementCompletedTasks(self: *TaskSemaphore) void {
        self.mtx.lock();
        self.num_complete += 1;
        self.mtx.unlock();
    }

    fn checkComplete(self: *TaskSemaphore) bool {
        self.mtx.lock();
        const wc = self.wait_count;
        const nc = self.num_complete;
        self.mtx.unlock();

        return nc == wc;
    }

    pub fn wait(self: *TaskSemaphore) void {
        while (!self.checkComplete()) {
            continue;
        }
    }
};

pub const Task = struct {
    next: ?*Task = null,
    prev: ?*Task = null,
    func: *const fn (*Task) void,
    semaphore_ptr: *TaskSemaphore,

    pub fn init(func: *const fn (*Task) void, semaphore: *TaskSemaphore) Task {
        return Task{ 
            .func = func,
            .semaphore_ptr = semaphore,
        };
    }

    pub fn run(self: *Task) void {
        @call(.auto, self.func, .{self});
        self.semaphore_ptr.incrementCompletedTasks();
    }
};

pub fn GContext(comptime T: type) type {
    return struct {
        const Self = @This();

        task: Task,
        value: T,

        pub fn init(comptime func: fn(*Task) void, value: T, semaphore: *TaskSemaphore) Self {
            return Self {
                .task = Task.init(func, semaphore),
                .value = value,
            };
        }

        pub inline fn ptrFromChild(task_ptr: *Task) *Self {
            return @fieldParentPtr(Self, task_ptr);
        }
    };
}

//pub fn main() !void {
//    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//    defer _ = gpa.deinit();
//    var allocator = gpa.allocator();
//    
//    var sl = try allocator.alloc(u32, 1_000_000);
//    for (sl, 0..) |*val, i| {
//        val.* = @intCast(i);
//    }
//
//    defer allocator.free(sl);
//    var tp = ThreadPool.init(allocator);
//    try tp.startThreads(.{});
//    var timer = try std.time.Timer.start();
//
//    var s1 = TaskSemaphore{};
//    var ctx = try tp.forEachNonBlocking(allocator, &s1, sl[0..], printMulti);
//    s1.wait();
//    allocator.free(ctx);
//    
//    try tp.forEach(sl[0..], printMulti);
//
//    const time = timer.read();
//    std.debug.print("time taken: {}ms\n", .{time / std.time.ns_per_ms});
//    tp.deinit(.{.finish_policy = .FinishAllTasks});
//}

fn printMulti(task: *Task) void {
    const ctx = GContext([]u32).ptrFromChild(task);
    for (ctx.value) |*num| {
        for (0..1000) |i| {
            if (i % 2 == 0) {
                num.* *= 3;
            } else {
                num.* /= 3;
            }
        }
    }
}

test "forEach-hardware-num-threads" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var allocator = gpa.allocator();
    
    var sl = try allocator.alloc(u32, 100_000);
    for (sl, 0..) |*val, i| {
        val.* = @intCast(i);
    }

    defer allocator.free(sl);
    var tp = ThreadPool.init(allocator);
    try tp.startThreads(.{});
    
    try tp.forEach(sl[0..], printMulti);
    
    tp.deinit(.{.finish_policy = .FinishAllTasks});
}

test "explicit-hardware-num-threads" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var allocator = gpa.allocator();
    
    var sl = try allocator.alloc(u32, 100_000);
    for (sl, 0..) |*val, i| {
        val.* = @intCast(i);
    }

    defer allocator.free(sl);
    var tp = ThreadPool.init(allocator);
    try tp.startThreads(.{});
    
    var s1 = TaskSemaphore{};
    const ctx = try tp.forEachNonBlocking(allocator, &s1, sl[0..], printMulti);
    s1.wait();
    allocator.free(ctx);
    
    tp.deinit(.{.finish_policy = .FinishAllTasks});
}