import { LightningElement, track } from "lwc";
import getMonthlyEvents from "@salesforce/apex/GoogleCalendarUtility.getMonthlyEvents";
import userId from "@salesforce/user/Id";

export default class GoogleCalendar extends LightningElement {
  @track weeks = [];
  @track isLoading = false;

  weekdays = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"];

  // Current view reference (year, month index 0-11)
  currentYear;
  currentMonthIndex;

  monthLabel = "";

  connectedCallback() {
    const today = new Date();
    this.currentYear = today.getFullYear();
    this.currentMonthIndex = today.getMonth();
    this.loadCurrentMonth();
  }

  handlePrevMonth = () => {
    const date = new Date(this.currentYear, this.currentMonthIndex, 1);
    date.setMonth(date.getMonth() - 1);
    this.currentYear = date.getFullYear();
    this.currentMonthIndex = date.getMonth();
    this.loadCurrentMonth();
  };

  handleNextMonth = () => {
    const date = new Date(this.currentYear, this.currentMonthIndex, 1);
    date.setMonth(date.getMonth() + 1);
    this.currentYear = date.getFullYear();
    this.currentMonthIndex = date.getMonth();
    this.loadCurrentMonth();
  };

  handleToday = () => {
    const today = new Date();
    this.currentYear = today.getFullYear();
    this.currentMonthIndex = today.getMonth();
    this.loadCurrentMonth();
  };

  handleEventClick = (evt) => {
    const link = evt.currentTarget?.dataset?.link;
    if (link) {
      window.open(link, "_blank");
    }
  };

  async loadCurrentMonth() {
    this.isLoading = true;
    try {
      const monthParam = `${this.currentYear}-${this.pad2(this.currentMonthIndex + 1)}`;
      const events = await getMonthlyEvents({ userId, month: monthParam });
      const eventMap = this.groupEventsByDay(events);
      this.monthLabel = this.formatMonthLabel(
        this.currentYear,
        this.currentMonthIndex
      );
      this.weeks = this.buildMonthGrid(
        this.currentYear,
        this.currentMonthIndex,
        eventMap
      );
    } catch (e) {
      // Minimal handling; clear grid so UI is not stuck
      console.error(
        "Failed to load calendar",
        e?.body?.message || e?.message || e
      );
      this.weeks = [];
    } finally {
      this.isLoading = false;
    }
  }

  buildMonthGrid(year, monthIndex, eventMap) {
    const firstOfMonth = new Date(year, monthIndex, 1);
    const startDayOfWeek = firstOfMonth.getDay(); // 0-6 Sun-Sat

    // Calculate days to ensure logic correctness (kept here if needed later)
    // const daysInMonth = new Date(year, monthIndex + 1, 0).getDate();

    // Determine the date for the first cell in the grid (Sunday of the first week)
    const gridStartDate = new Date(year, monthIndex, 1 - startDayOfWeek);

    const totalCells = 42; // 6 weeks * 7 days
    const weeks = [];
    for (let i = 0; i < totalCells; i += 1) {
      const cellDate = new Date(gridStartDate);
      cellDate.setDate(gridStartDate.getDate() + i);

      const isCurrentMonth = cellDate.getMonth() === monthIndex;
      const dayNumber = cellDate.getDate();
      const key = this.toISODate(cellDate);

      const cell = {
        key,
        iso: key,
        dayNumber,
        cellClass:
          "gc-cell slds-size_1-of-7 " +
          (isCurrentMonth ? "gc-in-month" : "gc-out-month"),
        events: eventMap.get(key) || []
      };

      const weekIndex = Math.floor(i / 7);
      if (!weeks[weekIndex]) {
        weeks[weekIndex] = [];
      }
      weeks[weekIndex].push(cell);
    }

    // Hide trailing empty weeks if the last week is entirely outside current month
    while (
      weeks.length > 5 &&
      weeks[weeks.length - 1].every((d) => d.cellClass.includes("gc-out-month"))
    ) {
      weeks.pop();
    }
    return weeks;
  }

  groupEventsByDay(events) {
    const byDay = new Map();
    if (!Array.isArray(events)) return byDay;

    events.forEach((evt) => {
      const start = evt?.eventStartTime ? new Date(evt.eventStartTime) : null;
      const end = evt?.eventEndTime ? new Date(evt.eventEndTime) : null;

      // For all-day events Apex provides a midnight date; if still missing, skip
      if (!start) {
        return;
      }
      const key = this.toISODate(start);
      const list = byDay.get(key) || [];

      const isAllDay = Boolean(evt?.isAllDay);
      let label;
      if (isAllDay) {
        // For all-day, show only the title
        label = evt?.label || 'Event';
      } else {
        const timeLabel = this.formatTimeRange(start, end);
        const parts = [];
        if (timeLabel) parts.push(timeLabel);
        if (evt?.label) parts.push(evt.label);
        label = (parts.join(' ').trim()) || 'Event';
      }

      const tooltip = this.formatTooltip(start, end, evt?.htmlLink);
      list.push({
        eventId: evt?.eventId || key,
        htmlLink: evt?.htmlLink,
        label,
        tooltip,
        isAllDay,
      });
      byDay.set(key, list);
    });

    // No sorting: preserve natural API order as requested
    return byDay;
  }

  formatMonthLabel(year, monthIndex) {
    const dt = new Date(year, monthIndex, 1);
    return new Intl.DateTimeFormat("en-US", {
      month: "long",
      year: "numeric"
    }).format(dt);
  }

  toISODate(d) {
    const y = d.getFullYear();
    const m = this.pad2(d.getMonth() + 1);
    const day = this.pad2(d.getDate());
    return `${y}-${m}-${day}`;
  }

  pad2(n) {
    return n < 10 ? `0${n}` : `${n}`;
  }

  formatTimeRange(start, end) {
    const opts = { hour: "2-digit", minute: "2-digit" };
    const startStr = start
      ? new Intl.DateTimeFormat("en-US", opts).format(start)
      : "";
    const endStr = end
      ? new Intl.DateTimeFormat("en-US", opts).format(end)
      : "";
    if (startStr && endStr) return `${startStr}`;
    if (startStr) return startStr;
    return "Event";
  }

  formatTooltip(start, end, link) {
    const range = this.formatTimeRange(start, end);
    return link ? `${range} • Open in Google` : range;
  }
}
